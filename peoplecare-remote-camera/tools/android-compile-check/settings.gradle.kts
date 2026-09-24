// Google's mirror of Maven Central is tried first: repo.maven.apache.org
// rate-limits shared CI/sandbox IP addresses (HTTP 429).
pluginManagement {
    repositories {
        maven("https://maven-central.storage-download.googleapis.com/maven2/")
        gradlePluginPortal()
        mavenCentral()
    }
}
dependencyResolutionManagement {
    repositories {
        maven("https://maven-central.storage-download.googleapis.com/maven2/")
        mavenCentral()
    }
}
rootProject.name = "android-compile-check"
