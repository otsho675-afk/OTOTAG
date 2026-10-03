import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("dev.flutter.flutter-gradle-plugin")
}


// Signing material is local/CI configuration, never committed source code.
val signingProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) propertiesFile.inputStream().use { load(it.reader(Charsets.UTF_8)) }
}
fun releaseSigningValue(name: String): String? {
    val environmentName = when (name) {
        "storeFile" -> "OTOTAG_KEYSTORE_PATH"
        "storePassword" -> "OTOTAG_STORE_PASSWORD"
        "keyAlias" -> "OTOTAG_KEY_ALIAS"
        else -> "OTOTAG_KEY_PASSWORD"
    }
    return providers.environmentVariable(environmentName).orNull
        ?: signingProperties.getProperty(name)
}
val signingNames = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val releaseRequested = gradle.startParameter.taskNames.any {
    val name = it.substringAfterLast(':')
    name.contains("Release", ignoreCase = true) &&
        (name.startsWith("bundle") || name.startsWith("assemble") || name.startsWith("package"))
}
if (releaseRequested) {
    val missing = signingNames.filter { releaseSigningValue(it).isNullOrBlank() }
    if (missing.isNotEmpty()) throw GradleException(
        "Release imza ayarları eksik: ${missing.joinToString()}. Proje kökünde configure-android-signing.ps1 çalıştırın."
    )
    if (!file(releaseSigningValue("storeFile")!!).isFile) throw GradleException(
        "Release keystore dosyası bulunamadı. Proje kökünde configure-android-signing.ps1 ile mevcut yükleme anahtarını seçin."
    )
}

// Use the same app configuration as Flutter; a source-code key is unnecessary.
val mapsConfig = rootProject.file("../config.env")
val configuredMapsKey = if (mapsConfig.exists()) mapsConfig.readLines()
    .firstOrNull { it.trim().startsWith("GOOGLE_MAPS_API_KEY=") }
    ?.substringAfter('=')?.trim()?.trim('"', '\'') ?: "" else ""
val googleMapsKey = providers.gradleProperty("OTOTAG_GOOGLE_MAPS_API_KEY")
    .orElse(providers.environmentVariable("OTOTAG_GOOGLE_MAPS_API_KEY"))
    .getOrElse(configuredMapsKey)
if (googleMapsKey.isBlank()) throw GradleException("config.env içinde GOOGLE_MAPS_API_KEY gerekli.")

android {
    namespace = "com.oto.tag"
    // Hata veren eklentilerin istediği minimum derleme sürümü 36 olarak ayarlandı
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        manifestPlaceholders["googleMapsApiKey"] = googleMapsKey
        applicationId = "com.oto.tag"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = releaseSigningValue("keyAlias")
            keyPassword = releaseSigningValue("keyPassword")
            storeFile = releaseSigningValue("storeFile")?.takeIf { it.isNotBlank() }?.let { file(it) }
            storePassword = releaseSigningValue("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
