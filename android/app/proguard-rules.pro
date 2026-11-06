# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

-keep class com.tencent.** { *; }

# WorkManager / Room
# Release 使用 proguard-android-optimize.txt, R8 会把 Room 里通过反射拼接类名的
# Class.getCanonicalName() 调用优化错误，导致启动时报：
#   Failed to create an instance of class androidx.work.impl.WorkDatabase.can
#   Unable to get provider androidx.startup.InitializationProvider
# 这里对 Room / WorkManager 关闭裁剪 + 混淆 +优化。

-keep class androidx.room.Room { *; }
-keep class androidx.room.RoomDatabase { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-dontwarn androidx.room.**
-dontwarn androidx.work.**

# ---- tencent_chat_uikit 原生代码（已迁入 app 模块）所需规则 ----
# 来源：原插件 android/consumer-rules.pro
# 该类库用 layout xml 中的全限定类名反射 inflate 自定义 View
# （RecordButtonView / ProgressRingView / BeautyStrengthSeekBar 等），
# com.tencent.** 的 keep 已覆盖类本身，这里补齐反射用到的属性和 Kotlin 元数据。
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-keep class kotlin.Metadata { *; }
-keepclassmembers class **$WhenMappings {
    <fields>;
}

# Parcelable.
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# Serializable.
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
