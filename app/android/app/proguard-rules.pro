# TFLite: the GPU delegate references an optional class that is not shipped.
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
# TFLite classes are reached from native code through JNI; keep them unshrunk.
-keep class org.tensorflow.lite.** { *; }
