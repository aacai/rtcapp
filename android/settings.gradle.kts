pluginManagement {
    val flutterSdkPath: String by settings
    extra["flutterSdkPath"] = file("local.properties").let {
        val properties = java.util.Properties()
        it.inputStream().use { stream -> properties.load(stream) }
        properties.getProperty("flutter.sdk") ?: error("flutter.sdk not set in local.properties")
    }

    includeBuild("${extra["flutterSdkPath"]}/packages/flutter_tools/gradle")

    repositories {
        maven {
            url = uri("https://maven.aliyun.com/repository/public/")
        }
        maven {
            url = uri("https://maven.aliyun.com/repository/central")
        }
        maven {
            url = uri("https://maven.aliyun.com/repository/google/")
        }
        maven {
            url = uri("https://maven.aliyun.com/repository/gradle")
        }
        maven {
            url = uri("https://jitpack.io")
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}

include(":app")
