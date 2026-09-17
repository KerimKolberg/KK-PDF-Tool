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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kerimkolberg.doc_scanner"
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
