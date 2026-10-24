# ONNX Runtime (flutter_onnxruntime): the Java classes are looked up from the
# native library by name, so R8 must not rename or remove them.
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# shared_preferences_android reaches Kotlin and its own classes through JNI,
# which R8 cannot see. Without these rules the release build failed with
# NoSuchMethodError / ClassNotFoundException (kotlin.Result, coroutines); found
# by tool/run_ocr_release_smoke.sh.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
