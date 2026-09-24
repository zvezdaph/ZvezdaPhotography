plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// RootEncoder (https://github.com/pedroSG94/RootEncoder), Apache-2.0.
// 2.8.1 is the latest stable release (checked on the upstream git tags).
val rootEncoderVersion: String = providers.gradleProperty("rootEncoderVersion").getOrElse("2.8.1")

android {
    namespace = "tv.peoplecare.remotecamera"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "tv.peoplecare.remotecamera"
        // Android 8.0+: notification channels, startForegroundService, Camera2.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Configure a real keystore for store builds (docs/ANDROID_SETUP.md).
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Camera, preview, H.264/AAC MediaCodec encoding, SRT and RTMPS in one engine.
    implementation("com.github.pedroSG94.RootEncoder:library:$rootEncoderVersion")
}
