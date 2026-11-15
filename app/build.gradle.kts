import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

// ---------------------------------------------------------------------------
// Signing (VoxFlow pattern, Agent-zero v2+v3 pattern):
// - Debug and release use DISTINCT keys, each FIXED across every build of
//   its type, so updates install over the old version. No per-run keys.
// - Debug: a fixed debug keystore committed as base64 TEXT in the repo
//   (keystore/debug.keystore.b64). Debug-only credentials, public by
//   design ("keel-debug"). Decoded here at configuration time into the
//   build directory; the binary keystore is never committed.
// - Release: android/key.properties is NEVER committed; CI writes it from
//   secrets. Without it, release builds fall back to the debug key so
//   that local release runs still work. The release keystore itself is
//   NOT generated here — that waits on the user's confirmation.
// - Both debug and release sign with v2 + v3 only (v1 disabled), the
//   Agent-zero pattern for Android 16 support.
// NOTE (learned from CI Runs #10/#11): fully-qualified java.util /
// java.io references do NOT resolve in this Kotlin DSL script, so the
// types are imported above and used unqualified. The store file is
// resolved here at top level because file() is not in scope inside the
// signingConfigs create() block.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseStoreFile = keystoreProperties.getProperty("storeFile")
    ?.let { rootProject.file(it) }

val debugKeystoreB64 = rootProject.file("keystore/debug.keystore.b64")
val debugKeystoreFile = layout.buildDirectory.file("keel/debug.keystore").get().asFile
if (debugKeystoreB64.exists()) {
    debugKeystoreFile.parentFile.mkdirs()
    debugKeystoreFile.writeBytes(Base64.getDecoder().decode(debugKeystoreB64.readText().trim()))
} else {
    logger.warn("Keel: keystore/debug.keystore.b64 not found — debug signing will fall back to the automatic debug key.")
}

android {
    namespace = "com.keel.manager"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.keel.manager"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
    }

    signingConfigs {
        getByName("debug") {
            if (debugKeystoreB64.exists()) {
                storeFile = debugKeystoreFile
                storePassword = "keel-debug"
                keyAlias = "keel-debug"
                keyPassword = "keel-debug"
            }
            enableV1Signing = false
            enableV2Signing = true
            enableV3Signing = true
        }
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = releaseStoreFile
            storePassword = keystoreProperties.getProperty("storePassword")
            enableV1Signing = false
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
        debug {
            // Debug stays unshrunk on purpose. Smoothness and premium
            // feel outrank size (user, 2026-11-15): report the actual
            // APK size honestly instead of cutting animation quality.
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // No key.properties (local dev): debug key so release
                // runs work. CI always supplies the real release key.
                signingConfigs.getByName("debug")
            }
            // No R8 / no shrinking in release either (user decision for
            // the Flutter builds: release must stay reproducible without
            // R8). Kept here for the same reason.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // java.time (LocalDate) is native from API 26, which is our
        // minSdk — no core-library desugaring is needed. Deliberately
        // NOT enabled: the Flutter build failed twice around desugaring
        // and its notifications plugin, and this app uses the platform
        // NotificationManager / AlarmManager directly instead.
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    // NOTE (CI Run #26, 2026-11-15): with the Compose Compiler Gradle
    // plugin applied above, no composeOptions block is needed — the plugin
    // carries the compiler version that matches Kotlin 2.1.0. The old
    // kotlinCompilerExtensionVersion setting is removed.

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.datastore.preferences)

    val composeBom = libs.androidx.compose.bom
    implementation(platform(composeBom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.material.icons.core)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.animation)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)

    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.room.testing)
    testImplementation(libs.robolectric)
    testImplementation(libs.kotlinx.coroutines.test)
}
