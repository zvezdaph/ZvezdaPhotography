import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Compile-only check of the native Android sources WITHOUT the Android SDK:
//  - android.*    from Robolectric's android-all (full framework, API 36)
//  - io.flutter.* from the Flutter engine jar of the local Flutter SDK
//  - RootEncoder  from its sources at the same tag used by the app (2.8.1)
//  - generated classes (R, BuildConfig) and androidx annotations as stubs
// It proves that the Kotlin code type-checks against the real APIs; it does
// not replace an APK build (resources, manifest merge, D8, packaging).
// Run it through scripts/check_android_sources.sh.
plugins { kotlin("jvm") version "2.4.0" }

val repoRoot = rootDir.resolve("../..").canonicalFile
val rootEncoderSrc = file(providers.gradleProperty("rootEncoderSrc").getOrElse("$repoRoot/build/rootencoder-src"))
val generatedStubs = file(providers.gradleProperty("generatedStubs").getOrElse("$repoRoot/build/android-compile-check/stubs"))
val flutterJar = providers.gradleProperty("flutterJar").orNull ?: error("-PflutterJar=<flutter.jar> is required")
val modules = listOf("common", "encoder", "rtmp", "rtsp", "srt", "udp", "whip", "library")
val appSources = "$repoRoot/apps/remote_camera/android/app/src/main/kotlin"

sourceSets {
    main {
        val rootEncoderDirs = modules.map { "$rootEncoderSrc/$it/src/main/java" }
        kotlin.srcDirs(rootEncoderDirs + listOf(appSources, "stubs", generatedStubs.path))
        java.srcDirs(rootEncoderDirs + listOf("stubs", generatedStubs.path))
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }
tasks.withType<JavaCompile>().configureEach { options.compilerArgs.addAll(listOf("-Xlint:none", "-nowarn")) }

dependencies {
    compileOnly("org.robolectric:android-all:16-robolectric-13921718")
    compileOnly(files(flutterJar))
    // Same versions as RootEncoder 2.8.1 (gradle/libs.versions.toml).
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("io.ktor:ktor-network:3.5.2")
    implementation("io.ktor:ktor-network-tls:3.5.2")
    implementation("org.bouncycastle:bcprov-jdk15to18:1.84")
    implementation("org.bouncycastle:bctls-jdk15to18:1.84")
    implementation("org.bouncycastle:bcpkix-jdk15to18:1.84")
}
