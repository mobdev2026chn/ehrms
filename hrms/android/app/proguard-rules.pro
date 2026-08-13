# Keep line numbers for Play Console crash deobfuscation (works with mapping.txt upload)
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
-keepattributes Signature,*Annotation*,EnclosingMethod,InnerClasses

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Google Play Services / Firebase
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.android.gms.**

# ML Kit (face detection, etc.)
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# OkHttp / Okio (common in plugins)
-dontwarn okhttp3.**
-dontwarn okio.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Kotlin
-keep class kotlin.Metadata { *; }

# JNI
-keepclasseswithmembernames class * {
    native <methods>;
}

# App entry
-keep class io.askeva.ektahr.MainActivity { *; }
