import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (VoxFlow pattern): a dedicated keel-release keystore.
// android/key.properties is NEVER committed; CI writes it from secrets.
// Without it, release builds fall back to the debug key so that
// `flutter run --release` still works locally. Debug and release keys
// must stay distinct and each fixed across builds of its type.
// NOTE: fully-qualified java.util/java.io references do NOT resolve in
// this Kotlin DSL script (CI Run #10: "Unresolved reference: util/io"),
// so the types are imported above and used unqualified. The store file
// is also resolved here at top level, because file() is not in scope
// inside the signingConfigs create() block (CI Run #10, line 48).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseStoreFile = keystoreProperties.getProperty("storeFile")
    ?.let { rootProject.file(it) }

android {
    namespace = "com.abybijo.keel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // CI Run #11: flutter_local_notifications requires core library
        // desugaring (checkDebugAarMetadata failure). Without this the
        // debug APK cannot build.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.abybijo.keel"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = releaseStoreFile
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // No key.properties (local dev): debug key so release
                // runs work. CI always supplies the real release key.
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // Core library desugaring, required by flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
