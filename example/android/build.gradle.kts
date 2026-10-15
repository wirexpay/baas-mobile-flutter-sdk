// The Wirex SDK is consumed as a published artifact: the Wirex Flutter plugins declare
// `com.wirexapp.baas:mobile-sdk` and resolve it from Maven Central.
//
// Repositories are declared HERE rather than in settings.gradle.kts on purpose. Using
// `dependencyResolutionManagement` with `PREFER_SETTINGS` displaces the repositories Flutter's own
// Gradle plugin injects — including the one that serves `io.flutter:flutter_embedding_debug` — so the
// build then cannot resolve the engine.
allprojects {
    repositories {
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
