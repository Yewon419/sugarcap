plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// 카탈로그 SSOT는 리포 루트 data/다(iOS와 같은 파일). 복사본을 커밋하지 않고 빌드가 가져간다.
val catalogDir: File = rootDir.resolve("../data").canonicalFile
val catalogFiles = fileTree(catalogDir) { include("catalog*.json") }

abstract class BundleCatalogs : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NAME_ONLY)
    abstract val catalogs: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val out = outputDir.get().asFile
        out.deleteRecursively()
        out.mkdirs()
        catalogs.forEach { it.copyTo(out.resolve(it.name)) }
    }
}

val bundleCatalogs = tasks.register<BundleCatalogs>("bundleCatalogs") {
    catalogs.from(catalogFiles)
}

android {
    namespace = "com.sugarcap.app"
    compileSdk = 37
    compileSdkMinor = 2

    defaultConfig {
        applicationId = "com.sugarcap.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(bundleCatalogs, BundleCatalogs::outputDir)
    }
}

tasks.withType<Test>().configureEach {
    inputs.files(catalogFiles).withPathSensitivity(PathSensitivity.NAME_ONLY)
    systemProperty("sugarcap.catalogDir", catalogDir.absolutePath)
    maxHeapSize = "2g"
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.11.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.13.0")

    testImplementation("junit:junit:4.13.2")
}
