// This file is auto generated style from Flutter templates.
// Simplified version compatible with Flutter 3.35.x.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Usa uma pasta de build compartilhada no nível acima (padrão Flutter).
rootProject.layout.buildDirectory.value(
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
)

subprojects {
    project.layout.buildDirectory.value(
        rootProject.layout.buildDirectory
            .dir(project.name)
            .get()
    )
}

subprojects {
    project.evaluationDependsOn(":app")
    dependencyLocking {
        ignoredDependencies.add("io.flutter:*")
        lockFile = file("${rootProject.projectDir}/project-${project.name}.lockfile")
        if (!project.hasProperty("local-engine-repo")) {
            lockAllConfigurations()
        }
    }
}

// Tarefa clean
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
