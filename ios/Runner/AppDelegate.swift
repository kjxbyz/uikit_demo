import Flutter
import UIKit
import tencent_chat_uikit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // tencent_chat_uikit 已不再是 Flutter 插件，这里手动注册其原生通道。
    // registrar(forPlugin:) 返回可选值，需显式解包后再传给 register(with:)。
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TencentChatUikitPlugin") else {
      NSLog("[uikit_demo] 无法获取 TencentChatUikitPlugin 的 registrar，聊天原生通道未注册")
      return
    }
    TencentChatUikitPlugin.register(with: registrar)
  }
}
