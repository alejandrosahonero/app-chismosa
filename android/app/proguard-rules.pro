# ProGuard / R8 rules.
#
# `minifyEnabled true` strips and renames everything it cannot see being used.
# Anything reached only through reflection or from native code must be kept
# here, otherwise the release build crashes where the debug build worked.
#
# After changing this file ALWAYS test a real release build — a debug build
# proves nothing about R8.

# --- Flutter ---------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- Google Mobile Ads / UMP ----------------------------------------------
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.ump.** { *; }
-dontwarn com.google.android.gms.ads.**

# --- Google Play Billing (in_app_purchase) --------------------------------
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.api.** { *; }

# --- Play Core (in_app_review, split installs) ----------------------------
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# --- Kotlin coroutines used by the plugins --------------------------------
-dontwarn kotlinx.coroutines.**

# --- Keep annotations and generic signatures ------------------------------
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# --- Crash readability ----------------------------------------------------
# Keep line numbers and hide the original file name so stack traces stay
# usable once symbols are uploaded to the crash reporting tool.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
