#
# tencent_chat_uikit 本地 pod：原 Flutter 插件 plugins/TUIKit_Flutter/chat/uikit 的
# iOS 原生代码（Classes/ + Assets/）已迁入本目录，作为普通本地组件由 Runner 直接引用，
# 不再走 Flutter 插件注册机制。
#
Pod::Spec.new do |s|
  s.name             = 'tencent_chat_uikit'
  s.version          = '1.0.0'
  s.summary          = 'Chat UI native code for uikit_demo (migrated from TUIKit_Flutter chat uikit plugin).'
  s.description      = <<-DESC
Chat UI native code for uikit_demo, migrated from the tencent_chat_uikit Flutter plugin.
                       DESC
  s.homepage         = 'https://trtc.io'
  s.license          = { :file => 'LICENSE' }
  s.author           = { 'Tencent Cloud' => 'trtc@tencent.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'tuikit_atomic_x'
  s.dependency 'Masonry'
  s.dependency 'AlbumPickerCore', '~> 1.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.platform = :ios, '14.0'
  s.resources = 'Assets/**/*'
  s.frameworks = 'Photos', 'AVFoundation', 'AudioToolbox', 'UIKit', 'SwiftUI'
end
