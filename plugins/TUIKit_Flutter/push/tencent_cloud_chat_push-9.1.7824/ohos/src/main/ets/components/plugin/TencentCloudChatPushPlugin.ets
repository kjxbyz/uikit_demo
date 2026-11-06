import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  NewWantListener,
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TIMPushListener, TIMPushManager, TIMPushMessage, TIMPushResult } from '@tencentcloud/timpush';

const CHANNEL_NAME: string = 'tencent_cloud_chat_push';
const RUN_ON_FLUTTER: number = 4;

const LOG_DOMAIN: number = 0xF700;
const LOG_TAG: string = 'TIMPushFlutter';

// TIMPush native SDK 的 NotificationClickProcessor 语义：
//   - `parameters.ext`      → 业务点击消息 ext（明文，派发给业务 listener）
//   - `parameters.clickExt` → SDK 内部统计上报 payload（非明文业务 ext）
// 华为 Push Kit 离线直接下发通知时，若后台没填 ext，want.parameters 里只有 clickExt。
// 此时 Plugin 层**不做 clickExt → ext 归一化**（避免把统计 payload 冒充业务 ext 派发），
// 但仍会 forward 该 want，让 native SDK 走完通知点击链路 —— 业务 listener 会收到一个
// 空 ext 的 `onNotificationClicked('')`，至少能感知"通知被点击"这一事件（业务可自行跳首页
// 兜底）。业务 ext 的正确来源修复属于 native TIMPush harmony SDK 责任（对齐 Android/iOS
// 从华为 push message 提取业务 ext 的路径）。
//
// 判定"是否为通知点击 want"仅使用 `clickExt`：
//   - 华为离线下发的通知点击 want 必带 clickExt（TIMPush 服务端塞入的统计字段），是可靠信号；
//   - native SDK `startLauncherAbility` 生成的 launcher want 只带 `ext` 而无 `clickExt`，
//     若把 `ext` 也纳入判定，会与 `notifyNotificationClicked` → `startLauncherAbility` →
//     `onNewWant` 形成死循环；因此判定条件保守到只认 `clickExt`。
//   - 在线本地通知点击走 `TIMPushClickActionAbility`（非 FlutterAbility），完全不经过
//     Plugin 的 `AbilityAware` 拦截，此处也无需考虑。
const PUSH_CLICK_EXT_KEY: string = 'clickExt';

/**
 * TencentCloudChatPushPlugin (HarmonyOS)
 *
 * Dart <=> HarmonyOS 原生 @tencentcloud/timpush 的桥接层。
 * 与 Android / iOS 实现保持一致的方法名、参数格式与"零侵入"接入体验：
 *
 *   - Android: `TencentCloudChatPushApplication` 在 `onCreate` 里通过 TUICore
 *     订阅通知点击事件并主动派发到 Flutter，客户仅需在 AndroidManifest 声明该
 *     Application 子类。
 *   - iOS: `TencentCloudChatPushPlugin` 在 `register` 时立即挂 `TIMPushListener`
 *     并通过 `tryNotifyDartOnNotificationClickEvent` 处理 Dart handler 未就绪的时序，
 *     客户无需自定义 AppDelegate 分发逻辑。
 *   - HarmonyOS: 通过 `AbilityAware` 接口拿到 `AbilityPluginBinding`，从
 *     `binding.getAbility().launchWant` 处理冷启动 want，用
 *     `binding.addOnNewWantListener` 处理热启动 want；将业务 ext 补齐后调用
 *     `TIMPushManager.notifyNotificationClicked`。客户 EntryAbility 与之前保持一致，
 *     无需增加任何解析代码。
 *
 * 华为 Push Kit 离线通知会直接拉起主 Ability 而绕过 `TIMPushClickActionAbility`，
 * 且 want 里业务 ext 存于 `clickExt` 字段，需要在 SDK 层归一化到 `ext` 再交给 TIMPush。
 *
 * Context 处理：TIMPush 内部会将传入 Context 强转 `common.UIAbilityContext` 用于
 * 申请通知权限，因此必须通过 AbilityAware 拿 `UIAbilityContext` 而不是 ApplicationContext。
 *
 * 仅实现 Dart 侧未标记 @Deprecated 的接口；Deprecated 接口由 Dart method_channel
 * 在 ohos 上直接短路，不会走到 native，因此这里也无需 case，会走 default 分支
 * 返回 notImplemented。
 */
export default class TencentCloudChatPushPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private applicationContext: common.Context | null = null;
  private abilityContext: common.UIAbilityContext | null = null;
  private pushListener: TIMPushListener | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;
  private newWantListener: NewWantListener | null = null;
  // 若 native 侧已收到通知点击但 Dart 侧 MethodCallHandler 未就绪，先缓存 ext，
  // 待 registerPush / addPushListener 到达 native 时（此时 Dart handler 一定已绑定）再补派发。
  // 对齐 iOS 的 `tryNotifyDartOnNotificationClickEvent` 和 Android 的
  // `scheduleCheckPluginInstanceAndNotifyForOnClick`。
  private pendingClickExt: string | null = null;
  private runningPlatformReported: boolean = false;

  constructor() {
  }

  getUniqueClassName(): string {
    return 'TencentCloudChatPushPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.applicationContext = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    this.installPushListener();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.uninstallPushListener();
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.applicationContext = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
    const ability = binding.getAbility();
    this.abilityContext = ability.context;

    // 冷启动：直接检查 launchWant。
    // flutter_ohos 在 UIAbility.onCreate 之后才走到这里，此时 launchWant 已由系统赋值。
    this.dispatchPushClickWantIfNeeded('onAttachedToAbility', ability.launchWant);

    // 热启动：注册 onNewWant 监听，Ability 收到新 want 时回调本插件。
    const plugin: TencentCloudChatPushPlugin = this;
    const listener: NewWantListener = {
      onNewWant: (want: Want, _launchParam: AbilityConstant.LaunchParam): void => {
        plugin.dispatchPushClickWantIfNeeded('onNewWant', want);
      },
    };
    this.newWantListener = listener;
    binding.addOnNewWantListener(listener);
  }

  onDetachedFromAbility(): void {
    if (this.abilityBinding !== null && this.newWantListener !== null) {
      this.abilityBinding.removeOnNewWantListener(this.newWantListener);
    }
    this.newWantListener = null;
    this.abilityBinding = null;
    this.abilityContext = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'registerPush':
          this.handleRegisterPush(call, result);
          return;

        case 'unRegisterPush':
          this.handleUnRegisterPush(result);
          return;

        case 'getRegistrationID':
          this.handleGetRegistrationID(result);
          return;

        case 'setRegistrationID':
          this.handleSetRegistrationID(call, result);
          return;

        case 'disablePostNotificationInForeground':
          this.handleDisableForegroundNotification(call, result);
          return;

        case 'callExperimentalAPI':
          this.handleCallExperimentalAPI(call, result);
          return;

        case 'addPushListener':
          // native 侧监听器随 plugin 生命周期常驻，此处仅回一次成功；
          // 同时 flush 之前缓存的通知点击事件（若有），保证 Dart handler 就绪后能收到。
          result.success(null);
          this.flushPendingClick();
          return;

        default:
          result.notImplemented();
      }
    } catch (err) {
      const e = err as Error;
      result.error('-1', e?.message ?? String(err), null);
    }
  }

  private handleRegisterPush(call: MethodCall, result: MethodResult): void {
    // TIMPush 内部会 as common.UIAbilityContext 用于申请通知权限，必须优先用 UIAbilityContext；
    // 若 AbilityAware 时序未到，才回退到 ApplicationContext（仅避免空指针，此时申请通知权限会失败）。
    const context: common.Context | null = this.abilityContext ?? this.applicationContext;
    if (context === null) {
      result.error('-1', 'Context is not attached yet', null);
      return;
    }

    const sdkAppIdRaw: string = (call.argument('sdkAppId') as string | null) ?? '';
    const appKeyRaw: string = (call.argument('appKey') as string | null) ?? '';
    // Dart 侧默认 `(sdkAppId ?? 0).toString()`，"0" 时应视为未传，避开 TIMPush 的 ERR_INVALID_SDK_APPID。
    const sdkAppIdNum: number = sdkAppIdRaw.length > 0 ? Number.parseInt(sdkAppIdRaw, 10) : 0;
    const sdkAppId: number | undefined =
      Number.isFinite(sdkAppIdNum) && sdkAppIdNum > 0 ? sdkAppIdNum : undefined;
    const appKey: string | undefined = appKeyRaw.length > 0 ? appKeyRaw : undefined;

    this.ensureRunningPlatformReported()
      .then((): Promise<TIMPushResult> => {
        return TIMPushManager.getInstance().registerPush(context, sdkAppId, appKey);
      })
      .then((res: TIMPushResult) => {
        result.success(res?.message ?? '');
        // registerPush 到达 native 时 Dart 侧 MethodCallHandler 一定已绑定
        // （Dart 的 registerPush 内部会先绑定 handler 再 invokeMethod），可安全 flush。
        this.flushPendingClick();
      })
      .catch((err: TIMPushResult) => {
        result.error(String(err?.code ?? '-1'), err?.message ?? 'registerPush failed', null);
      });
  }

  private handleUnRegisterPush(result: MethodResult): void {
    TIMPushManager.getInstance()
      .unRegisterPush()
      .then(() => {
        result.success(null);
      })
      .catch((err: TIMPushResult) => {
        result.error(String(err?.code ?? '-1'), err?.message ?? 'unRegisterPush failed', null);
      });
  }

  private handleGetRegistrationID(result: MethodResult): void {
    TIMPushManager.getInstance()
      .getRegistrationID()
      .then((res: TIMPushResult) => {
        const data = res?.data as Record<string, string> | undefined;
        result.success(data?.registrationID ?? res?.message ?? '');
      })
      .catch((err: TIMPushResult) => {
        result.error(String(err?.code ?? '-1'), err?.message ?? 'getRegistrationID failed', null);
      });
  }

  private handleSetRegistrationID(call: MethodCall, result: MethodResult): void {
    const regId: string = (call.argument('registrationID') as string | null) ?? '';
    TIMPushManager.getInstance()
      .setRegistrationID(regId)
      .then(() => {
        result.success(null);
      })
      .catch((err: TIMPushResult) => {
        result.error(String(err?.code ?? '-1'), err?.message ?? 'setRegistrationID failed', null);
      });
  }

  private handleDisableForegroundNotification(call: MethodCall, result: MethodResult): void {
    const raw: string = (call.argument('disablePostNotificationInForeground') as string | null) ?? 'false';
    const disable: boolean = raw.toLowerCase() === 'true';
    TIMPushManager.getInstance().disablePostNotificationInForeground(disable);
    result.success(null);
  }

  private handleCallExperimentalAPI(call: MethodCall, result: MethodResult): void {
    const api: string = (call.argument('api') as string | null) ?? '';
    const param: ESObject = call.argument('param');
    TIMPushManager.getInstance()
      .callExperimentalAPI(api, param)
      .then((res: TIMPushResult) => {
        result.success(res?.data ?? res?.message ?? null);
      })
      .catch((err: TIMPushResult) => {
        result.error(String(err?.code ?? '-1'), err?.message ?? 'callExperimentalAPI failed', null);
      });
  }

  /**
   * 告知 TIMPush SDK 当前运行环境为 Flutter (PUSH_SDK_RUN_ON_FLUTTER = 4)。
   * 需要在 registerPush 之前完成，与 uniapp 侧同样机制对齐；否则 SDK 默认按 NATIVE 处理，
   * 会影响多端同步自己发消息的过滤逻辑（isMultiSyncPushMessage）及后端上报的 platform 字段。
   * 仅上报一次即可，失败不阻塞主流程。
   */
  private ensureRunningPlatformReported(): Promise<void> {
    if (this.runningPlatformReported) {
      return Promise.resolve();
    }
    const payload: string = JSON.stringify({ runningPlatform: RUN_ON_FLUTTER });
    return TIMPushManager.getInstance().callExperimentalAPI('setPushConfig', payload)
      .then(() => {
        this.runningPlatformReported = true;
      })
      .catch(() => {
        // 上报失败不阻塞后续 registerPush
      });
  }

  /**
   * 冷启动 / 热启动通知点击 want 统一处理入口。
   *
   * `AbilityAware` 拿到的 `launchWant` / `onNewWant` 是**所有** want（应用图标启动、
   * deeplink、通知点击、以及 native SDK `startLauncherAbility` 自触发的 launcher want
   * 等），必须做场景过滤，否则会：
   *   1. 应用图标启动被误报"通知被点击"；
   *   2. `notifyNotificationClicked → startLauncherAbility → onNewWant → ...` 死循环。
   * 判定条件仅用 `clickExt`（详见文件顶部注释）。
   *
   * 命中判定后 forward 给 `TIMPushManager.notifyNotificationClicked`，让 native SDK 走完
   * 标准派发链路 —— 经 `TIMPushProvider` 派发到本插件已挂载的
   * `TIMPushListener.onNotificationClicked` 再 invokeMethod 到 Dart。业务 listener 拿到
   * 的 ext 具备"诚实"语义：
   *   - 有值：来自 native SDK 明确的业务 ext（`parameters.ext`）
   *   - 空串：本次通知没有透传业务 ext（例如后台推送时未填 ext 字段，业务侧可选择跳首页兜底）
   *
   * 业务 ext 从华为 Push Kit push message 中的正确提取属于 native TIMPush harmony SDK
   * 责任（当前 SDK 未实现，对齐 Android/iOS 后可解决）。
   */
  private dispatchPushClickWantIfNeeded(stage: string, want: Want | undefined): void {
    const params = want?.parameters as Record<string, ESObject> | undefined;
    if (params === undefined || params === null) {
      return;
    }

    const clickExtValue: ESObject = params[PUSH_CLICK_EXT_KEY];
    const clickExt: string = typeof clickExtValue === 'string' ? clickExtValue : '';
    if (clickExt.length === 0) {
      // 非通知点击 want（应用图标启动 / deeplink / native SDK 自触发的 launcher want 等），忽略。
      return;
    }

    const context = this.abilityContext;
    if (context === null) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        '%{public}s: abilityContext missing, drop push click', stage);
      return;
    }

    hilog.info(LOG_DOMAIN, LOG_TAG,
      '%{public}s: forward push click want to TIMPush SDK (clickExt.len=%{public}d)',
      stage, clickExt.length);
    TIMPushManager.getInstance()
      .notifyNotificationClicked(context, want)
      .catch((err: TIMPushResult) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          '%{public}s: notifyNotificationClicked failed code=%{public}s msg=%{public}s',
          stage, String(err?.code ?? ''), err?.message ?? '');
      });
  }

  private installPushListener(): void {
    const plugin: TencentCloudChatPushPlugin = this;
    const listener: TIMPushListener = {
      onMessageReceived: (message: TIMPushMessage): void => {
        plugin.forwardRecvPushMessage(message);
      },
      onRevokePushMessage: (messageID: string): void => {
        plugin.channel?.invokeMethod('onRevokePushMessage', messageID);
      },
      onNotificationClicked: (ext: string): void => {
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'native onNotificationClicked: channel=%{public}s, ext=%{public}s',
          plugin.channel === null ? 'null' : 'ready',
          ext ?? '');
        // 先缓存，Dart handler 未就绪时也能在后续 registerPush/addPushListener 到达时补派发。
        plugin.pendingClickExt = ext;
        if (plugin.channel === null) {
          return;
        }
        // 双通道派发：对齐 Android / iOS，兼容 `addPushListener` 与
        // `registerPush(onNotificationClicked:)` 两条 Dart 侧回调路径。
        plugin.channel.invokeMethod('onNotificationClicked', ext);
        plugin.channel.invokeMethod('on_notification_clicked', ext);
      },
    };
    this.pushListener = listener;
    TIMPushManager.getInstance().addPushListener(listener);
  }

  private uninstallPushListener(): void {
    if (this.pushListener !== null) {
      TIMPushManager.getInstance().removePushListener(this.pushListener);
      this.pushListener = null;
    }
  }

  private forwardRecvPushMessage(message: TIMPushMessage): void {
    const payload: Record<string, string> = {
      'title': message.title,
      'desc': message.desc,
      'ext': message.ext,
      'messageID': message.messageID,
    };
    this.channel?.invokeMethod('onRecvPushMessage', payload);
  }

  /**
   * Dart 侧在 registerPush / addPushListener 前会先 setMethodCallHandler，
   * 因此这两个方法到达 native 时可以安全把缓存的通知点击 ext 再派发一次，
   * 覆盖冷启动阶段 Dart handler 尚未绑定就丢失的场景。
   *
   * 语义：`pendingClickExt === null` 表示没有 pending；空串 `''` 也是合法的 pending
   * （腾讯云控制台推送不填 ext 时 native 派发的就是空串），必须补派发，否则业务
   * listener 收不到"通知被点击"这一事件。
   */
  private flushPendingClick(): void {
    const ext = this.pendingClickExt;
    if (ext === null) {
      return;
    }
    this.pendingClickExt = null;
    if (this.channel === null) {
      return;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'flushPendingClick: replay cached ext to Dart (len=%{public}d)', ext.length);
    this.channel.invokeMethod('onNotificationClicked', ext);
    this.channel.invokeMethod('on_notification_clicked', ext);
  }
}
