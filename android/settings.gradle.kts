import org.gradle.api.initialization.resolve.RepositoriesMode

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // ✅ 先用国内镜像
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }

        // ✅ Flutter 自己的仓库
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }

        // ✅ 再加回官方仓库，让 Gradle 插件（com.android.application）能解析到
        google()
        gradlePluginPortal()
        // mavenCentral() 对插件来说一般不必要，这里可以先不加
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        // ✅ 依赖优先走阿里云
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }

        // ✅ Flutter 仓库
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }

        // 可以选择是否加回官方的：
        google()
        // 如果你现在网络+Clash 够稳，也可以加上：
        // mavenCentral()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
