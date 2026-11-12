import groovy.json.JsonSlurper
import java.security.MessageDigest
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.hedefender.simpledocscan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Phase 6.5: the final id (it was com.example.one_click_scan). Android sees a
        // different app: nothing is migrated from the old one. See ADR-034.
        applicationId = "io.github.hedefender.simpledocscan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing (ADR-034, docs/RELEASE.md). The key lives outside the repo;
    // android/key.properties (git-ignored) only points to it. Without that file
    // the release build is signed with the debug key, so a clone still builds.
    val keyProperties = Properties()
    val keyPropertiesFile = rootProject.file("key.properties")
    val hasReleaseKey = keyPropertiesFile.exists()
    if (hasReleaseKey) {
        keyPropertiesFile.inputStream().use { keyProperties.load(it) }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
                logger.warn(
                    "WARNING: release signed with debug key, not for distribution " +
                        "(android/key.properties not found, see docs/RELEASE.md)."
                )
            }
            // R8 on: the ONNX Runtime classes are reached from native code, so
            // proguard-rules.pro keeps them (see docs/PHASE_2_VALIDATION.md).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

// The OCR models are not in git (tool/fetch_ocr_models.sh downloads them). A
// build without them, or with a file whose SHA-256 differs from
// assets/ocr/manifest.json, must fail here rather than ship a broken app.
val verifyOcrModels by tasks.registering {
    group = "verification"
    description = "Fails the build when an OCR model is missing or does not match its SHA-256."
    val manifest = rootProject.file("../assets/ocr/manifest.json")
    val modelsDir = rootProject.file("../assets/ocr/models")
    doLast {
        @Suppress("UNCHECKED_CAST")
        val files = (JsonSlurper().parse(manifest) as Map<String, Any>)["files"] as List<Map<String, Any>>
        val problems = mutableListOf<String>()
        for (entry in files) {
            val name = entry["name"] as String
            val file = File(modelsDir, name)
            when {
                !file.exists() -> problems += "$name: missing"
                file.length() != (entry["bytes"] as Number).toLong() -> problems += "$name: wrong size"
                else -> {
                    val digest = MessageDigest.getInstance("SHA-256")
                    file.inputStream().use { input ->
                        val buffer = ByteArray(1 shl 16)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            digest.update(buffer, 0, read)
                        }
                    }
                    val hex = digest.digest().joinToString("") { "%02x".format(it) }
                    if (hex != entry["sha256"]) problems += "$name: SHA-256 does not match the manifest"
                }
            }
        }
        if (problems.isNotEmpty()) {
            throw GradleException(
                "OCR models are not ready: " + problems.joinToString("; ") +
                    ". Run tool/fetch_ocr_models.sh to download and verify them."
            )
        }
    }
}

tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(verifyOcrModels) }
