# Flutter's engine is reached through JNI, so R8 cannot see the references.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core is referenced by Flutter's deferred-components support, which this
# app does not use. Without this, R8 fails on the missing classes.
-dontwarn com.google.android.play.core.**
