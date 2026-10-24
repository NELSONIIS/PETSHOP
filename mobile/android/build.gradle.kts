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
subprojects {
    if (project.name != "app") {
        project.afterEvaluate {
            val android = project.extensions.findByName("android")
            if (android != null) {
                try {
                    val mInt = android.javaClass.methods.firstOrNull { 
                        (it.name == "compileSdkVersion" || it.name == "setCompileSdkVersion") && 
                        it.parameterTypes.size == 1 && 
                        (it.parameterTypes[0] == Int::class.javaPrimitiveType || it.parameterTypes[0] == java.lang.Integer::class.java)
                    }
                    if (mInt != null) {
                        mInt.invoke(android, 36)
                    } else {
                        val mStr = android.javaClass.methods.firstOrNull { 
                            (it.name == "compileSdkVersion" || it.name == "setCompileSdkVersion") && 
                            it.parameterTypes.size == 1 && it.parameterTypes[0] == String::class.java
                        }
                        mStr?.invoke(android, "android-36")
                    }
                } catch (_: Exception) {
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
