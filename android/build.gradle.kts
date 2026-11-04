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

// 1. 定义你需要操作的指定模块路径列表（例如 ":feature:login", ":core:base" 等）
val targetModules = setOf(":tencent_rtc_sdk", ":tuikit_atomic_x", ":tencent_calls_uikit", ":tencent_chat_uikit")

subprojects {
    val subproject = this

    // 2. 如果当前子模块不在指定的列表中，直接跳过
    if (!targetModules.contains(subproject.path)) {
        return@subprojects
    }

    val raiseCompileSdk = {
        val androidExt = subproject.extensions.findByName("android")
        if (androidExt != null && androidExt.javaClass.methods.any { it.name == "getCompileSdk" }) {
            val appProject = rootProject.findProject(":app")
            val appAndroid = appProject?.extensions?.findByName("android")

            val appSdk = appAndroid?.let { ext ->
                val method = ext.javaClass.methods.firstOrNull { it.name == "getCompileSdk" }
                method?.invoke(ext) as? Int
            }

            val targetSdk = Math.max(appSdk ?: 35, 35)

            val currentSdkMethod = androidExt.javaClass.methods.firstOrNull { it.name == "getCompileSdk" }
            val currentSdk = currentSdkMethod?.invoke(androidExt) as? Int

            if (currentSdk != null && currentSdk < targetSdk) {
                val setSdkMethod = androidExt.javaClass.methods.firstOrNull { it.name == "setCompileSdk" && it.parameterTypes.size == 1 }
                setSdkMethod?.invoke(androidExt, targetSdk)
            }
        }
    }

    if (subproject.state.executed) {
        raiseCompileSdk()
    } else {
        subproject.afterEvaluate {
            raiseCompileSdk()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
