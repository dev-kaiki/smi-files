// App-level Gradle script usando Kotlin DSL, compatível com Flutter 3.38.x

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Ajuste se o seu pacote for diferente
    namespace = "com.example.smi_files"

    // Usa as versões que o Flutter fornece
    compileSdk = flutter.compileSdkVersion

    // Versão do NDK instalada no seu SDK (já baixada)
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        // Ajuste se quiser mudar o ID final do app
        applicationId = "com.example.smi_files"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Usa a debug keystore só pra facilitar o build por enquanto
            signingConfig = signingConfigs.getByName("debug")

            // Desliga shrink de código e de recursos pra evitar o erro
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

// Aponta pro código Flutter
flutter {
    source = "../.."
}
