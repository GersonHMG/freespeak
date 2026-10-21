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
// The onnxruntime plugin pins `compileSdkVersion 33`, but the AndroidX
// libraries it pulls in now require 34+, which fails :onnxruntime's
// checkDebugAarMetadata. Raise every Android subproject to the same compileSdk
// the app uses. Set reflectively so this does not depend on the Android Gradle
// Plugin types being on the root project's classpath.
//
// This must be registered before the evaluationDependsOn block below, which
// evaluates :app eagerly — afterEvaluate cannot be added to a project that has
// already been evaluated.
subprojects {
    fun raiseCompileSdk() {
        val androidExtension = extensions.findByName("android") ?: return
        runCatching {
            androidExtension.javaClass
                .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(androidExtension, 36)
        }
    }
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
