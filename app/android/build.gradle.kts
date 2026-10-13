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

// Some plugins (tflite_flutter) set Java 1.8 but no Kotlin target, so Kotlin
// defaults to the JDK running Gradle and the build fails. Match Kotlin to Java.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val javaTask = project.tasks.named<JavaCompile>(name.replace("Kotlin", "JavaWithJavac"))
        compilerOptions.jvmTarget.set(
            javaTask.map { org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(it.targetCompatibility) },
        )
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
