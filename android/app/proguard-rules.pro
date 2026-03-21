# Flutter/Android defaults
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# NewPipeExtractor — keep classes needed for n-param deobfuscation
-keep class org.schabi.newpipe.extractor.** { *; }

# Rhino (JavaScript engine used by NewPipeExtractor for n-param deobfuscation)
-keep class org.mozilla.javascript.** { *; }
-dontwarn org.mozilla.javascript.**

# Suppress warnings for optional dependencies not available on Android
-dontwarn com.google.re2j.Matcher
-dontwarn com.google.re2j.Pattern
-dontwarn java.beans.BeanDescriptor
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor
-dontwarn javax.script.ScriptEngineFactory

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

# Flutter optional Play Store deferred components (not used in this build)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
