# OpenCast Android 构建指南

## 项目结构

```
opencast-android/
├── app/
│   ├── build.gradle.kts          # 应用构建配置
│   └── src/main/
│       ├── AndroidManifest.xml   # 应用清单
│       ├── java/com/opencast/app/
│       │   ├── MainActivity.kt   # 主 Activity
│       │   ├── OpenCastApplication.kt
│       │   ├── di/AppModule.kt   # Hilt 依赖注入
│       │   ├── discovery/        # 设备发现
│       │   │   ├── DeviceDiscoveryManager.kt
│       │   │   └── DiscoveredDevice.kt
│       │   ├── service/          # 前台服务
│       │   │   └── ScreenCaptureService.kt
│       │   ├── ui/               # UI 层
│       │   │   ├── screen/       # 页面
│       │   │   │   ├── HomeScreen.kt
│       │   │   │   └── CastingScreen.kt
│       │   │   ├── theme/        # 主题
│       │   │   └── viewmodel/    # ViewModel
│       │   └── webrtc/           # WebRTC 核心
│       │       ├── WebRTCClient.kt
│       │       ├── ScreenCapturer.kt
│       │       └── SignalingClient.kt
│       └── res/                  # 资源文件
├── build.gradle.kts              # 根构建配置
├── settings.gradle.kts           # 项目设置
└── gradle.properties             # Gradle 属性
```

## 环境要求

- **JDK**: 17 或更高版本
- **Android Studio**: Hedgehog (2023.1.1) 或更高版本
- **Android SDK**: API 34 (Android 14)
- **最低 SDK**: API 24 (Android 7.0)

## 依赖库

| 库 | 版本 | 用途 |
|----|------|------|
| Kotlin | 1.9.22 | 编程语言 |
| Compose BOM | 2024.02.00 | UI 框架 |
| Hilt | 2.50 | 依赖注入 |
| WebRTC | 1.0.32006 | 实时通信 |
| OkHttp | 4.12.0 | 网络请求 |
| JmDNS | 3.5.8 | mDNS 设备发现 |

## 构建步骤

### 1. 打开项目

使用 Android Studio 打开 `opencast-android` 文件夹。

### 2. 同步项目

Android Studio 会自动下载依赖并同步项目。如果遇到问题，可以手动同步：

```bash
./gradlew sync
```

### 3. 构建 APK

```bash
# 调试版本
./gradlew assembleDebug

# 发布版本
./gradlew assembleRelease
```

APK 输出位置：
- 调试版：`app/build/outputs/apk/debug/app-debug.apk`
- 发布版：`app/build/outputs/apk/release/app-release.apk`

### 4. 安装到设备

```bash
# 连接设备后执行
./gradlew installDebug

# 或使用 adb
adb install app/build/outputs/apk/debug/app-debug.apk
```

## 运行前配置

### 1. 信令服务器

确保信令服务器已启动：

```bash
cd ../opencast-signaling-server
npm install
npm start
```

默认地址：`ws://192.168.1.100:8443`

### 2. 修改信令服务器地址

在 `SignalingClient.kt` 中修改默认地址：

```kotlin
private const val DEFAULT_SIGNALING_URL = "ws://你的服务器IP:8443"
```

### 3. 接收端设备

确保接收端（Android TV 或浏览器）已启动并连接到同一网络。

## 权限说明

应用需要以下权限：

| 权限 | 用途 |
|------|------|
| `INTERNET` | 网络通信 |
| `FOREGROUND_SERVICE` | 前台服务（Android 9+） |
| `FOREGROUND_SERVICE_MEDIA_PROJECTION` | 屏幕采集前台服务（Android 14+） |
| `POST_NOTIFICATIONS` | 显示投屏状态通知（Android 13+） |
| `MediaProjection` | 屏幕采集（运行时授权） |

## 常见问题

### 1. WebRTC 库下载失败

检查网络连接，或配置国内镜像：

```kotlin
// 在 settings.gradle.kts 中添加
pluginManagement {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
}
```

### 2. 编译错误：找不到符号

清理并重新构建：

```bash
./gradlew clean
./gradlew build
```

### 3. 运行时崩溃：MissingForegroundServiceTypeException

确保 `ScreenCaptureService` 已正确声明前台服务类型：

```xml
<service
    android:name=".service.ScreenCaptureService"
    android:foregroundServiceType="mediaProjection"
    ... />
```

## 调试技巧

### 查看日志

```bash
adb logcat -s OpenCast:D WebRTCClient:D SignalingClient:D
```

### 网络调试

使用 Chrome DevTools 检查 WebSocket 连接：

1. 打开 `chrome://inspect`
2. 找到你的设备
3. 检查 WebSocket 帧

## 发布构建

### 签名配置

在 `app/build.gradle.kts` 中添加签名配置：

```kotlin
android {
    signingConfigs {
        create("release") {
            storeFile = file("opencast.keystore")
            storePassword = System.getenv("STORE_PASSWORD")
            keyAlias = "opencast"
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }
    
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
```

### 生成签名密钥

```bash
keytool -genkey -v -keystore opencast.keystore -alias opencast -keyalg RSA -keysize 2048 -validity 10000
```

## 许可证

MIT License - 详见根目录 LICENSE 文件
