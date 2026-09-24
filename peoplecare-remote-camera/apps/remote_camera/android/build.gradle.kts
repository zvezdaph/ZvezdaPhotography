allprojects {
    repositories {
        // Optional local Maven repository with RootEncoder built from source
        // (scripts/build_rootencoder_from_source.sh), used when JitPack is unreachable.
        val localRootEncoder = providers.gradleProperty("rootEncoderMavenRepo").orNull
        if (!localRootEncoder.isNullOrBlank()) {
            maven {
                url = uri(localRootEncoder)
                content { includeGroupByRegex("com\\.github\\.pedroSG94.*") }
            }
        }
        google()
        mavenCentral()
        // JitPack is only allowed to serve RootEncoder artifacts.
        maven {
            url = uri("https://jitpack.io")
            content { includeGroupByRegex("com\\.github\\.pedroSG94.*") }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
