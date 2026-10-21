import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clé de signature stable : sans elle, chaque compilation est signée avec une clé différente et Android refuse
// de mettre à jour l'application déjà installée (« incompatible »). Fournie par le workflow GitHub (secrets).
val cleProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "bf.vipcolis.vip_colis"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "bf.vipcolis.vip_colis"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("tchi") {
            if (cleProps.getProperty("storeFile") != null) {
                storeFile = rootProject.file(cleProps.getProperty("storeFile"))
                storePassword = cleProps.getProperty("storePassword")
                keyAlias = cleProps.getProperty("keyAlias")
                keyPassword = cleProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Clé stable si fournie, sinon clé de debug (compilation locale).
            signingConfig = if (cleProps.getProperty("storeFile") != null)
                signingConfigs.getByName("tchi") else signingConfigs.getByName("debug")
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
