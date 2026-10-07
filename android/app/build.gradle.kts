import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
fun signingValue(property: String, environment: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val releaseStore = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")?.let { file(it) }
val releaseAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseStorePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseSigningReady = releaseStore?.isFile == true && releaseAlias != null &&
    releaseStorePassword != null && releaseKeyPassword != null
// Check the actual task graph: debug builds and IDE configuration need no key.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release", ignoreCase = true) } &&
        !releaseSigningReady) {
        throw GradleException("Release signing missing. Set storeFile, storePassword, keyAlias and " +
            "keyPassword in android/key.properties, or the ANDROID_KEYSTORE_PATH, " +
            "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD environment variables.")
    }
}

android {
    namespace = "io.devopen.dondurma"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStore
            storePassword = releaseStorePassword
            keyAlias = releaseAlias
            keyPassword = releaseKeyPassword
        }
    }

    defaultConfig {
        applicationId = "io.devopen.dondurma"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
