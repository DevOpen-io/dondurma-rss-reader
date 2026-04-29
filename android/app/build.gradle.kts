import java.util.Properties
import java.io.FileInputStream

// 1. Keystore ayarlarını okuma kısmı (Kotlin DSL uyumlu)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreExists = keystorePropertiesFile.exists()

if (!keystoreExists) {
    println("⚠️  WARNING: key.properties not found. Release signing disabled.")
    println("    Place key.properties in android/ directory or builds will use debug config.")
} else {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
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

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        // 2. İmzalama ayarları (Kotlin DSL'de atamalar '=' ile yapılır)
        create("release") {
            if (keystoreExists) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            } else {
                // key.properties yoksa debug imzalama kullanılır
                println("⚠️  WARNING: Release signing config will use debug keystore (key.properties missing)")
            }
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
            // 3. Oluşturduğumuz release konfigürasyonunu bağlama
            signingConfig = signingConfigs.getByName("release")

            // Kod küçültme ve temizleme (Play Store için genelde true önerilir)
            isMinifyEnabled = false
            isShrinkResources = false
            
            // Warning: when key.properties missing, uses debug keystore
            if (!keystoreExists) {
                println("⚠️  NOTICE: Release build using debug keystore (key.properties missing)")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
