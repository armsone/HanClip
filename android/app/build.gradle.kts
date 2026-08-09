plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

val sharedGeneratedAssetsDir = layout.buildDirectory.dir("generated/shared-assets")
val syncSharedAssets by tasks.registering(org.gradle.api.tasks.Sync::class) {
    from(rootProject.file("../HanClip/Resources/Fonts")) {
        include("Paperlogy-7Bold.ttf", "NEXONLv1GothicRegular.ttf", "Poppins-Regular.ttf")
        into("fonts")
        eachFile {
            name = when (name) {
                "Paperlogy-7Bold.ttf" -> "paperlogy_bold.ttf"
                "NEXONLv1GothicRegular.ttf" -> "nexon_lv1_gothic.ttf"
                "Poppins-Regular.ttf" -> "poppins_regular.ttf"
                else -> name
            }
        }
    }
    from(rootProject.file("../HanClip/Resources/font-licenses")) {
        include("*.txt", "README.md")
        into("font-licenses")
    }
    from(rootProject.file("../HanClip/Assets.xcassets/CollectionPin.imageset")) {
        include("CollectionPin.png")
        into("images")
        rename("CollectionPin.png", "collection_pin.png")
    }
    into(sharedGeneratedAssetsDir)
    includeEmptyDirs = false
}

android {
    namespace = "com.hanclip.android"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.hanclip.android"
        minSdk = 26
        targetSdk = 37
        versionCode = 482
        versionName = "1.0.1"
    }

    buildTypes {
        create("releaseQa") {
            initWith(getByName("release"))
            isDebuggable = false
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release", "debug")
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // AGP 9 source sets do not accept Provider values. preBuild below owns the
    // generation dependency, so expose the resolved directory as a regular File.
    sourceSets.getByName("main").assets.directories.add(sharedGeneratedAssetsDir.get().asFile.absolutePath)
}

tasks.named("preBuild").configure { dependsOn(syncSharedAssets) }

dependencies {
    val media3Version = "1.10.1"
    val cameraXVersion = "1.4.1"

    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.exifinterface:exifinterface:1.4.2")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
    implementation("androidx.media3:media3-ui-compose:$media3Version")
    implementation("androidx.media3:media3-transformer:$media3Version")
    implementation("androidx.media3:media3-effect:$media3Version")
    implementation("androidx.camera:camera-camera2:$cameraXVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraXVersion")
    implementation("androidx.camera:camera-video:$cameraXVersion")
    implementation("androidx.camera:camera-view:$cameraXVersion")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
