# ONNX Runtime (flutter_onnxruntime): the Java classes are looked up from the
# native library by name, so R8 must not rename or remove them. Same rule as
# the main app (found there by its release smoke test; here by a SIGABRT
# "JNI DETECTED ERROR IN APPLICATION: java_class == null" on the first read).
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
