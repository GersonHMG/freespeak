import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload key for Play. key.properties and the .jks it points to stay out of
// version control; without them the release build falls back to debug keys.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.gersonhmg.freespeak"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.gersonhmg.freespeak"
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
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles("proguard-rules.pro")
        }
    }

    // JNA's own arm64 libjnidispatch.so is built with an old NDK that Play
    // flags for 16 KB devices. src/main/jniLibs carries a rebuild with NDK
    // r28 (see third_party/jnidispatch), and app sources come first in the
    // merge, so pickFirst keeps ours over the one in the JNA aar.
    packaging {
        jniLibs {
            pickFirsts += "lib/arm64-v8a/libjnidispatch.so"
        }
    }
}

// Release builds ship 64-bit ARM only. Plugin native libs (ONNX Runtime,
// Vosk) come for every ABI regardless of --target-platform, and the 32-bit
// ARM and x86_64 copies cost ~57 MB of APK. An `ndk.abiFilters` in the
// release block does not work: the Flutter Gradle plugin adds its own
// filters for every target platform, and filters are unioned. Excluding at
// packaging time runs after that merge. Debug and profile keep every ABI, so
// the emulator still works.
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(
            listOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**"),
        )
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
