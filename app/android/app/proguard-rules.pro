# R8 keep rules for release builds.

# ONNX Runtime: its JNI code looks up ai.onnxruntime classes by name.
-keep class ai.onnxruntime.** { *; }
