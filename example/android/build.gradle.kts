// The Wirex SDK is consumed as a published artifact: the Wirex Flutter plugins declare
// `com.wirexapp.baas:mobile-sdk` and resolve it from Maven Central.
//
// Repositories are declared HERE rather than in settings.gradle.kts on purpose. Using
// `dependencyResolutionManagement` with `PREFER_SETTINGS` displaces the repositories Flutter's own
// Gradle plugin injects — including the one that serves `io.flutter:flutter_embedding_debug` — so the
// build then cannot resolve the engine.

// DEV ONLY: `WIREX_SDK_REPO` is a Maven folder holding a from-source build of the native SDK, and the
// version comes from `$WIREX_ANDROID_SDK/VERSION`. Without them the published artifact is used.
val wirexSdkRepo: String? = System.getenv("WIREX_SDK_REPO")?.takeIf { it.isNotEmpty() }
if (wirexSdkRepo != null) {
    val checkout = System.getenv("WIREX_ANDROID_SDK") ?: throw GradleException("WIREX_SDK_REPO needs WIREX_ANDROID_SDK")
    extra["wirexSdkVersion"] = file("$checkout/VERSION").readText().trim()
}

allprojects {
    repositories {
        // Exclusive: the SDK comes only from that folder, whatever order other plugins add repositories in.
        if (wirexSdkRepo != null) {
            exclusiveContent {
                forRepository { maven { url = uri(wirexSdkRepo) } }
                filter { includeModule("com.wirexapp.baas", "mobile-sdk") }
            }
        }
        google()
        mavenCentral()
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
