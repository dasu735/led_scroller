// android/build.gradle.kts

// Top-level build file. Repositories are centralized in settings.gradle.kts
// so don't declare repositories here.

buildscript {
    // Keep minimal; plugin management handled in settings.gradle.kts
    dependencies {
        // classpath entries are not required here because pluginManagement handles them.
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
