import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_push/common/common_defines.dart';
import 'package:tencent_cloud_chat_push/common/tim_push_listener.dart';
import 'package:tencent_cloud_chat_push/tencent_cloud_chat_push_modal.dart';

import 'tencent_cloud_chat_push_platform_interface.dart';

/// An implementation of [TencentCloudChatPushPlatform] that uses method channels.
class MethodChannelTencentCloudChatPush extends TencentCloudChatPushPlatform {
  /// The method channel used to interact with the native platform.
  final _methodChannel = const MethodChannel('tencent_cloud_chat_push');

  final TencentCloudChatPushModal _tencentCloudChatPushModal = TencentCloudChatPushModal();

  /// HarmonyOS 平台判定。标准 Flutter SDK 没有 `Platform.isOhos`，
  /// 用 `Platform.operatingSystem` 做字符串比对可以在标准 SDK 和
  /// Flutter-OH 分支下同时通过编译。
  static bool get _isOhos => Platform.operatingSystem == 'ohos';

  /// HarmonyOS 上未实现/不支持的接口统一返回错误码，避免假装成功导致上层误判。
  /// code=-1 与既有跨平台 fallback（`Platform.isIOS || Platform.isAndroid || _isOhos`
  /// 之外的兜底分支）保持一致。
  static TencentCloudChatPushResult<T> _ohosUnsupported<T>(String api) =>
      TencentCloudChatPushResult<T>(
        code: -1,
        errorMessage: '$api is not supported on HarmonyOS',
      );

  @override
  Future<String?> getPlatformVersion() async {
    // @Deprecated：ohos 侧不实现。返回类型是 String? 而非 TencentCloudChatPushResult，
    // 无法携带错误码/错误描述；直接返回 null 明确表达"不支持"，同时避免走到 native
    // 抛 MissingPluginException。
    if (_isOhos) {
      return null;
    }
    final version = await _methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<TencentCloudChatPushResult> registerOnNotificationClickedEvent({
    required Function({required String ext, String? userID, String? groupID}) onNotificationClicked,
  }) async {
    try {
      _tencentCloudChatPushModal.onNotificationClicked = onNotificationClicked;
      _methodChannel.setMethodCallHandler(_tencentCloudChatPushModal.handleMethod);
      // ohos 上仅绑定 Dart handler，不 invoke native：通知点击派发由 native 的
      // TIMPushListener.onNotificationClicked 通过双通道 invokeMethod 直接触发 modal handler。
      // 这里 handler 绑定确实生效，因此返回 code=0 是正确语义；同时 `TencentCloudChatPush.registerPush`
      // 内部依赖本方法返回 0 才会继续走 registerPush 主流程，改为错误码会破坏 ohos 注册链路。
      if (Platform.isAndroid || Platform.isIOS) {
        await _methodChannel.invokeMethod("registerOnNotificationClickedEvent");
      }
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> registerOnAppWakeUpEvent({
    required VoidCallback onAppWakeUpEvent,
  }) async {
    // @Deprecated & ohos 上原生未派发 wake-up 事件流，绑定 handler 也不会被回调；
    // 明确返回错误，避免调用方误以为已生效。
    if (_isOhos) {
      return _ohosUnsupported('registerOnAppWakeUpEvent');
    }
    try {
      _tencentCloudChatPushModal.onAppWakeUp = onAppWakeUpEvent;
      _methodChannel.setMethodCallHandler(_tencentCloudChatPushModal.handleMethod);
      if (Platform.isAndroid) {
        await _methodChannel.invokeMethod("registerOnAppWakeUpEvent");
      }
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> registerPush({
    int? sdkAppId,
    String? appKey,
  }) async {
    try {
      if (Platform.isIOS || Platform.isAndroid || _isOhos) {
        final res = await _methodChannel.invokeMethod("registerPush", {
          "sdkAppId": (sdkAppId ?? 0).toString(),
          "appKey": (appKey ?? ""),
        });
        return TencentCloudChatPushResult(code: 0, data: res);
      }
      return TencentCloudChatPushResult(code: -1);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> unRegisterPush() async {
    try {
      await _methodChannel.invokeMethod("unRegisterPush");
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> disableAutoRegisterPush() async {
    // @Deprecated：ohos 不实现，返回错误避免调用方误认为生效
    if (_isOhos) {
      return _ohosUnsupported('disableAutoRegisterPush');
    }
    try {
      await _methodChannel.invokeMethod("disableAutoRegisterPush");
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> enableBackupChannels() async {
    // @Deprecated：ohos 不实现，返回错误避免调用方误认为生效
    if (_isOhos) {
      return _ohosUnsupported('enableBackupChannels');
    }
    try {
      await _methodChannel.invokeMethod("enableBackupChannels");
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> setCustomFCMRing({
    required String channelId,
    required String ringName,
    required bool enable,
  }) async {
    // @Deprecated：FCM 专用，ohos 不实现，返回错误避免调用方误认为生效
    if (_isOhos) {
      return _ohosUnsupported('setCustomFCMRing');
    }
    try {
      await _methodChannel.invokeMethod("setCustomFCMRing", {
        "fcm_push_channel_id": channelId,
        "private_ring_name": ringName,
        "enable_fcm_private_ring": enable.toString(),
      });
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> setPushBrandId({required int brandId}) async {
    // @Deprecated：ohos 不实现，返回错误避免调用方误认为生效
    if (_isOhos) {
      return _ohosUnsupported('setPushBrandId');
    }
    try {
      await _methodChannel.invokeMethod("setPushBrandId", {
        "brand_id": brandId.toString(),
      });
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult<int>> getPushBrandId() async {
    // @Deprecated：ohos 不实现，返回错误避免调用方误取到 0 当作有效品牌 ID
    if (_isOhos) {
      return _ohosUnsupported<int>('getPushBrandId');
    }
    try {
      final res = await _methodChannel.invokeMethod("getPushBrandId");
      return TencentCloudChatPushResult(code: 0, data: int.tryParse(res.toString()));
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult<String>> checkPushStatus({required int brandID}) async {
    try {
      final res = await _methodChannel.invokeMethod("checkPushStatus", {
        "brand_id": brandID.toString(),
      });
      return TencentCloudChatPushResult(code: 0, data: res);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> setBusID({required int busID}) async {
    try {
      if (Platform.isIOS) {
        await _methodChannel.invokeMethod("setBusId", {"busId": busID});
      }
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> setApplicationGroupID({required String applicationGroupID}) async {
    // @Deprecated & iOS-only 语义，ohos 不实现，返回错误避免调用方误认为生效
    if (_isOhos) {
      return _ohosUnsupported('setApplicationGroupID');
    }
    try {
      await _methodChannel.invokeMethod("setApplicationGroupID", {"applicationGroupID": applicationGroupID});
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult<String>> getAndroidPushToken() async {
    // @Deprecated & Android-only 语义，ohos 不实现，返回错误避免调用方误取空串当作有效 token
    if (_isOhos) {
      return _ohosUnsupported<String>('getAndroidPushToken');
    }
    try {
      final res = await _methodChannel.invokeMethod("getAndroidPushToken");
      return TencentCloudChatPushResult(code: 0, data: res);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> setAndroidPushToken({
    required String businessID,
    required String pushToken,
  }) async {
    // @Deprecated & Android-only 语义，ohos 不实现，返回错误避免调用方误认为生效
    if (_isOhos) {
      return _ohosUnsupported('setAndroidPushToken');
    }
    try {
      await _methodChannel.invokeMethod("setAndroidPushToken", {
        "business_id": businessID,
        "push_token": pushToken,
      });
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> setAndroidCustomConfigFile({
    required String configs,
  }) async {
    // @Deprecated & Android-only 语义，ohos 不实现，返回错误避免调用方误认为生效
    if (_isOhos) {
      return _ohosUnsupported('setAndroidCustomConfigFile');
    }
    try {
      await _methodChannel.invokeMethod("setAndroidCustomConfigFile", {
        "configs": configs,
      });
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> setXiaoMiPushStorageRegion({
    required int region,
  }) async {
    // @Deprecated & Android-only 语义，ohos 不实现，返回错误避免调用方误认为生效
    if (_isOhos) {
      return _ohosUnsupported('setXiaoMiPushStorageRegion');
    }
    try {
      await _methodChannel.invokeMethod("setXiaoMiPushStorageRegion", {
        "region": region.toString(),
      });
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> getRegistrationID() async {
    try {
      final res = await _methodChannel.invokeMethod("getRegistrationID");
      return TencentCloudChatPushResult(code: 0, data: res);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> setRegistrationID({
    required String registrationID,
  }) async {
    try {
      await _methodChannel.invokeMethod("setRegistrationID", {
        "registrationID": registrationID,
      });
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<void> addPushListener({
    required TIMPushListener listener,
  }) async {
    try {
      _tencentCloudChatPushModal.addPushListener(listener);
      _methodChannel.setMethodCallHandler(_tencentCloudChatPushModal.handleMethod);
      await _methodChannel.invokeMethod("addPushListener");
      return;
    } on PlatformException catch (e) {
      return;
    }
  }

  @override
  Future<void> removePushListener({
    required TIMPushListener listener,
  }) async {
    _tencentCloudChatPushModal.removePushListener(listener);
    return;
  }

  @override
  Future<TencentCloudChatPushResult> forceUseFCMPushChannel({
    required bool enable,
  }) async {
    try {
      await _methodChannel.invokeMethod("forceUseFCMPushChannel", {
        "forceUseFCMPushChannel": enable.toString(),
      });
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> disablePostNotificationInForeground({
    required bool disable,
  }) async {
    try {
      await _methodChannel.invokeMethod("disablePostNotificationInForeground", {
        "disablePostNotificationInForeground": disable.toString(),
      });
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> createNotificationChannel({
    required String channelID,
    required String channelName,
    String? channelDesc,
    String? channelSound,
  }) async {
    try {
      await _methodChannel.invokeMethod("createNotificationChannel", {
        "channel_id": channelID,
        "channel_name": channelName,
        "channel_desc": (channelDesc ?? ""),
        "channel_sound": (channelSound ?? ""),
      });
      return TencentCloudChatPushResult(code: 0);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

  @override
  Future<TencentCloudChatPushResult> callExperimentalAPI({
    required String api,
    Object? param,
  }) async {
    try {
      if (Platform.isIOS || Platform.isAndroid || _isOhos) {
        final res = await _methodChannel.invokeMethod("callExperimentalAPI", {
          "api": api,
          "param": param,
        });
        return TencentCloudChatPushResult(code: 0, data: res);
      }
      return TencentCloudChatPushResult(code: -1);
    } on PlatformException catch (e) {
      return TencentCloudChatPushResult(
        code: int.tryParse(e.code) ?? -1,
        errorMessage: e.message,
      );
    }
  }

}
