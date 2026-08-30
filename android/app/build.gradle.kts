import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 🟢 ตัดไฟล์ ListenableFuture เดี่ยวๆ ทิ้ง เพื่อป้องกัน Duplicate Class
configurations.all {
    exclude(group = "com.google.guava", module = "listenablefuture")
}

// โหลดไฟล์ key.properties สำหรับ Release Key
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.ncds_voice_app_vol1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // 📍 กำหนดค่า Compile Options ระดับ Android (เวอร์ชัน 17 ตามโปรเจกต์)
    compileOptions {
        isCoreLibraryDesugaringEnabled = true // 👈 เปิดใช้งาน Desugaring ที่นี่
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.ncds_voice_app_vol1"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true // 👈 ใช้รูปแบบ Kotlin DSL
    }

    // 🔴 1. เพิ่มบล็อก signingConfigs สำหรับผูกลายเซ็น Release
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // 🔴 2. เปลี่ยนจาก "debug" เป็น "release"
            signingConfig = signingConfigs.getByName("release")
            
            // เพิ่มบรรทัดนี้ เพื่อเปิดระบบย่อขนาดโค้ด (ช่วยลดขนาดแอป)
            isMinifyEnabled = true
            
            // เพิ่มบรรทัดนี้ เพื่อลดขนาดทรัพยากร (รูป/ไฟล์ ที่ไม่ได้ใช้)
            isShrinkResources = true
            
            // สั่งให้ระบบไปอ่านกฎป้องกันการลบโค้ดจากไฟล์ proguard-rules.pro
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module"
            )
            pickFirsts += listOf(
                "**/libcrypto.so",
                "**/libssl.so"
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

// 🟢 เพิ่ม dependencies ตัวจริงเข้ามา
dependencies {
    implementation("androidx.concurrent:concurrent-futures:1.1.0")
    implementation("com.google.guava:guava:32.1.3-android")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4") // 👈 รูปแบบวงเล็บและ Double Quotes สำหรับ .kts
}

