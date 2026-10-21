# R8 keep rules for release builds.

# JNA (used by Vosk). libjnidispatch looks up classes, fields and methods by
# name (e.g. Pointer.peer), and JNA maps Java interfaces onto native symbols
# through reflection, so nothing in it may be renamed or removed.
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { *; }
-dontwarn java.awt.**
-dontwarn com.sun.jna.**

# Vosk: LibVosk's method names are the native function names JNA binds to.
-keep class org.vosk.** { *; }

# ONNX Runtime: its JNI code looks up ai.onnxruntime classes by name.
-keep class ai.onnxruntime.** { *; }
