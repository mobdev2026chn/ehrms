import org.gradle.api.tasks.compile.JavaCompile

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
    // Suppress javac warning for legacy -source/-target flags used by some plugins.
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }
}

// Plugin modules (e.g. google_maps_flutter_android) still run lintVital*; AGP lint uses older
// Kotlin vs maps-utils 2.3. Disable those tasks after they are created (safe with evaluationDependsOn).
gradle.projectsEvaluated {
    subprojects.forEach { p ->
        p.tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
