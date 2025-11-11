plugins {
    id("com.android.application")
    id("kotlin-android")
    // Der Flutter Gradle Plugin MUSS nach Android/Kotlin kommen:
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.dateiexplorer_tachograph"

    // Flutter Variablen beibehalten
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.dateiexplorer_tachograph"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    // >>> WICHTIG: Kotlin-DSL Syntax!
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        // Wähle 17, wenn du AGP 8.x/Gradle 8.x nutzt (empfohlen).
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Falls du lieber bei 1.8 bleiben willst:
        // sourceCompatibility = JavaVersion.VERSION_1_8
        // targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "17" // oder "1.8" passend zu oben
    }

    buildTypes {
        release {
            // damit `flutter run --release` funktioniert
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // >>> Kotlin-DSL: Klammern + Anführungszeichen
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // Native gomobile artefact (android.lib.aar) dropped into app/libs
    implementation(files("libs/Androidlib.aar"))

    // deine übrigen Dependencies kommen hier mit implementation("group:artifact:version")
    // z.B.: implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
