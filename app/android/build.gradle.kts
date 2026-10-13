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
// Old plugins (tflite_flutter: compileSdk 31) compile against an SDK older than
// their AndroidX dependencies require. compileSdk only affects the build, not
// which phones the app runs on. Registered before :app is force-evaluated below.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
        if (name != "app" && android is com.android.build.gradle.BaseExtension) {
            android.compileSdkVersion(36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins (tflite_flutter) set Java 1.8 but no Kotlin target, so Kotlin
// defaults to the JDK running Gradle and the build fails. Match Kotlin to Java.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val javaTaskName = name.replace("Kotlin", "JavaWithJavac")
        // project.provider, not javaTask.map: map would add a task dependency (a cycle).
        compilerOptions.jvmTarget.set(
            project.provider {
                val java = project.tasks.getByName(javaTaskName) as JavaCompile
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(java.targetCompatibility)
            },
        )
    }
    // javac 22+ fails on type annotations whose classes are not on the compile
    // classpath: camera_android_camerax with CameraX 1.5 needs concurrent-futures.
    if (name == "camera_android_camerax") {
        plugins.withId("com.android.library") {
            dependencies.add("compileOnly", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
