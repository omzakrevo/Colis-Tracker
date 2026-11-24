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
// Certaines bibliothèques (flutter_blue_plus…) sont compilées avec un compileSdk trop ancien pour leurs dépendances.
// Appel par réflexion : fonctionne quelle que soit la version du plugin Android Gradle.
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            val android = project.extensions.findByName("android")
            if (android != null) {
                try {
                    android.javaClass.getMethod("setCompileSdk", Integer::class.javaObjectType).invoke(android, 36)
                } catch (e: Exception) {
                    try {
                        android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(android, 36)
                    } catch (e2: Exception) {
                        println("compileSdk non modifié pour " + project.name)
                    }
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
