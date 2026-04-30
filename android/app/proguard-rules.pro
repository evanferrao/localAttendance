# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter Play Store split/deferred components (not used, suppress R8 warnings)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.app.FlutterPlayStoreSplitApplication
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# TFLite
-keep class org.tensorflow.** { *; }
-keepclassmembers class org.tensorflow.** { *; }

# ML Kit — keep all vision classes to avoid R8 missing class errors
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }

# ML Kit text recognition language modules (referenced but optional)
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Hive
-keep class com.hive.** { *; }
-keepclassmembers class * {
    @com.hive.annotations.HiveField *;
}

# General
-keepattributes *Annotation*
-keepattributes Signature
-dontwarn sun.misc.**
