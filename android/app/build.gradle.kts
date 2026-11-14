plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.kerimkolberg.doc_scanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Fixed: Google sign-in is registered for this id, and Android treats
        // a different id as a different app.
        applicationId = "com.kerimkolberg.doc_scanner"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml / --build-number (see .github/workflows/build.yml).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystorePath = System.getenv("DOCSCANNER_KEYSTORE_PATH")
    val hasReleaseKeystore = !keystorePath.isNullOrEmpty()

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystorePath!!)
                storePassword = System.getenv("DOCSCANNER_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("DOCSCANNER_KEY_ALIAS")
                keyPassword = System.getenv("DOCSCANNER_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Uses a stable keystore (via env vars, see .github/workflows/build.yml)
            // so the app's SHA-1 fingerprint stays the same across builds -
            // required for Google Sign-In's Android OAuth client to keep working.
            // Falls back to the debug key when those env vars aren't set (e.g.
            // building locally without the release keystore).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
    // Bundled Latin-script OCR model: works fully offline from the first
    // launch (no Play Services download), used via MainActivity.kt.
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
