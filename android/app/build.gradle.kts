import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload keystore credentials. `key.properties` is git-ignored: create it from
// `key.properties.example`. When the file is missing (fresh clone, CI without
// secrets) the release build falls back to the debug signing config so
// `flutter build` still works locally.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.alejandrosahonero.aja"

    // Pinned to 37: required by permission_handler 13 and
    // flutter_secure_storage 11. Do not lower it.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications: it uses java.time APIs that
        // do not exist below API 26, and minSdk is 24. Without this the build
        // fails at :app:checkDebugAarMetadata.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // CANNOT be changed after the first publication on Google Play.
        applicationId = "com.alejandrosahonero.aja"
        minSdk = 24
        // Play requires targeting a recent API every year (deadline is usually
        // 31 August). `flutter.targetSdkVersion` tracks the Flutter stable
        // default; pin it manually if you need a specific value.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Code shrinking + resource shrinking: the single biggest win on
            // APK/AAB size. Keep proguard-rules.pro in sync with the plugins.
            // (PNG crunching is already enabled by default for release.)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            isMinifyEnabled = false
        }
    }
}

dependencies {
    // Backport of java.time & friends for API < 26. Version floor comes from
    // flutter_local_notifications (>= 2.1.4).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
