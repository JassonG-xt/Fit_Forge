# ══════════════════════════════════════════════════════════════════
#  FitForge ProGuard / R8 rules
# ══════════════════════════════════════════════════════════════════
#
# Consumed by `buildTypes.release` when `isMinifyEnabled = true`.
# Add only what is strictly necessary — over-keeping defeats shrinking.
# ──────────────────────────────────────────────────────────────────

# ─── Flutter embedding ───
# Required for plugin channels and Dart runtime interop.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ─── Lottie (assets/animations/*.json) ───
# Lottie uses reflection to resolve layer/shape classes.
-keep class com.airbnb.lottie.** { *; }
-dontwarn com.airbnb.lottie.**

# ─── flutter_local_notifications (Sprint 3) ───
# BroadcastReceiver is referenced by AndroidManifest and must survive R8.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# ─── health (Android Health Connect, Sprint 3) ───
-keep class androidx.health.connect.** { *; }
-keep class androidx.health.platform.** { *; }
-dontwarn androidx.health.**

# ─── Kotlin metadata (needed by many plugins using kotlinx.serialization / reflection) ───
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# ─── General Android conventions ───
# Preserve signatures for generics, annotations for reflection, and inner-class references.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Preserve native method bindings (JNI).
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve Parcelable CREATOR fields (plugins like path_provider use them).
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# Preserve enum values (used by Flutter plugins for bi-directional channels).
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
