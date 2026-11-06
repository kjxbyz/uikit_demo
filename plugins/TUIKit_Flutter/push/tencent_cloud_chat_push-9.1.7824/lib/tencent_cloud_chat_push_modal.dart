import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_push/common/tim_push_listener.dart';
import 'package:tencent_cloud_chat_push/common/tim_push_message.dart';
import 'package:tencent_cloud_chat_push/common/utils.dart';

class TencentCloudChatPushModal {
  TencentCloudChatPushModal._internal();

  factory TencentCloudChatPushModal() => _instance;
  static final TencentCloudChatPushModal _instance = TencentCloudChatPushModal._internal();

  // registerPush(onNotificationClicked:) / registerOnNotificationClickedEvent 传入的回调。
  // 通过 setter 拦截，赋值时若存在 [_pendingOnClickExt] 立即回放，避免"native 派发已到达、
  // 但 Dart 侧回调尚未注册"造成的事件丢失（典型场景：离线冷启动，registerPush 走异步 await，
  // native 侧 `on_notification_clicked` 派发早于 Dart 端赋值）。
  // 与 native `TIMPushProvider.mNotificationExtInfo` 的 replay-on-addPushListener 机制对称。
  Function({required String ext, String? userID, String? groupID})? _onNotificationClicked;
  String? _pendingOnClickExt;

  Function({required String ext, String? userID, String? groupID})? get onNotificationClicked =>
      _onNotificationClicked;

  set onNotificationClicked(
      Function({required String ext, String? userID, String? groupID})? callback) {
    _onNotificationClicked = callback;
    // 语义：`_pendingOnClickExt == null` 表示没有 pending；空串 `''` 也是合法的 pending
    // （腾讯云控制台推送不填 ext 时 native 派发的就是空串），必须 replay，否则业务回调
    // 会永久丢事件。
    final pending = _pendingOnClickExt;
    if (callback != null && pending != null) {
      _pendingOnClickExt = null;
      try {
        final ParseExtInfoResult conversationInfo =
            TencentCloudChatPushUtils.parseExtInfo(pending);
        callback(
          ext: pending,
          userID: conversationInfo.userID,
          groupID: conversationInfo.groupID,
        );
      } catch (err, errorStack) {
        debugPrint("$err $errorStack");
      }
    }
  }

  VoidCallback? onAppWakeUp;
  List<TIMPushListener> timPushListenerList = [];
  String? mNotificationExtInfo;

  Future<dynamic> handleMethod(MethodCall call) async {
    switch (call.method) {
      case "on_notification_clicked":
        debugPrint("TencentCloudChatPush: ${call.arguments}");
        final ext = call.arguments.toString();
        if (_onNotificationClicked == null) {
          // 回调尚未注册（registerPush 还未 await 到 registerOnNotificationClickedEvent），
          // 先缓存 ext，待 [onNotificationClicked] setter 赋值时立即回放。
          _pendingOnClickExt = ext;
          break;
        }
        final ParseExtInfoResult conversationInfo = TencentCloudChatPushUtils.parseExtInfo(ext);
        _onNotificationClicked!.call(
          ext: ext,
          userID: conversationInfo.userID,
          groupID: conversationInfo.groupID,
        );
        break;
      case "on_app_wake_up":
        onAppWakeUp?.call();
        break;
      case "onRecvPushMessage":
        debugPrint("onRecvPushMessage: ${TimPushMessage.fromJson(call.arguments).toLogString()}");
        timPushListenerList.forEach((listener) {
          try {
            listener.onRecvPushMessage(TimPushMessage.fromJson(call.arguments));
          } catch (err, errorStack) {
            debugPrint("$err $errorStack");
          }
        });
        break;
      case "onRevokePushMessage":
        debugPrint("onRevokePushMessage: ${call.arguments.toString()}");
        timPushListenerList.forEach((listener) {
          try {
            listener.onRevokePushMessage(call.arguments.toString());
          } catch (err, errorStack) {
            debugPrint("$err $errorStack");
          }
        });
        break;
      case "onNotificationClicked":
        debugPrint("onNotificationClicked: ${call.arguments.toString()}");
        mNotificationExtInfo = call.arguments.toString();
        notificationClicked();
        break;
      default:
        throw UnsupportedError("Unrecognized Event");
    }
  }

  void notificationClicked() {
    if (mNotificationExtInfo == null || timPushListenerList.isEmpty) {
      return;
    }

    timPushListenerList.forEach((listener) {
      try {
        String ext = mNotificationExtInfo!;
        listener.onNotificationClicked(ext);
      } catch (err, errorStack) {
        debugPrint("$err $errorStack");
      }
    });

    mNotificationExtInfo = null;
  }

  void addPushListener(TIMPushListener listener) {
    if (timPushListenerList.contains(listener)) {
      return;
    }

    timPushListenerList.add(listener);
    notificationClicked();
  }

  void removePushListener(TIMPushListener listener) {
    if (timPushListenerList.isEmpty) {
      return;
    }

    if (timPushListenerList.contains(listener)) {
      timPushListenerList.remove(listener);
    }
  }
}
