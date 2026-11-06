package com.example.uikit_demo

import com.tencent.cloud.tuikit.flutter.tuichatkit.TencentChatUikitPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // tencent_chat_uikit 已不再是 Flutter 插件，这里手动注册其原生通道
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(TencentChatUikitPlugin())
    }
}
