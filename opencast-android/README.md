# OpenCast - Android 投屏应用

OpenCast 是一个基于 Kotlin + Jetpack Compose + WebRTC 技术栈的 Android 投屏应用，支持将 Android 设备屏幕实时投屏到同一局域网内的接收端设备。

## 技术架构

### 核心技术栈

| 技术 | 用途 |
|------|------|
| Kotlin | 主要开发语言 |
| Jetpack Compose | 声明式 UI 框架 |
| WebRTC (google-webrtc) | 实时音视频传输 |
| Hilt | 依赖注入框架 |
| OkHttp WebSocket | 信令服务器通信 |
| JmDNS | mDNS 局域网设备发现 |
| Kotlin Coroutines & Flow | 异步编程 |

### 架构设计

```
┌─────────────────────────────────────────────┐
│                   UI 层                      │
│  ┌──────────┐  ┌──────────────┐             │
│  │HomeScreen│  │CastingScreen │             │
│  └────┬─────┘  └──────┬───────┘             │
│       │               │                     │
│  ┌────┴───────────────┴──────┐              │
│  │   ViewModel 层            │              │
│  │ ┌────────────┐ ┌────────┐│              │
│  │ │DeviceVM    │ │CastingVM││              │
│  │ └─────┬──────┘ └───┬────┘│              │
│  └───────┼────────────┼──────┘              │
├──────────┼────────────┼─────────────────────┤
│          │    业务逻辑层 │                     │
│  ┌───────┴──────┐ ┌────┴──────────┐         │
│  │DeviceDiscovery│ │WebRTCClient   │         │
│  │Manager       │ │  ├─ScreenCapturer│       │
│  │              │ │  └─SignalingClient│      │
│  └──────────────┘ └───────────────┘         │
├─────────────────────────────────────────────┤
│              服务层                           │
│  ┌──────────────────────────────┐           │
│  │ ScreenCaptureService         │           │
│  │ (前台服务 - Android 14+)     │           │
│  └──────────────────────────────┘           │
└─────────────────────────────────────────────┘
```

### 模块说明

#### 1. WebRTC 模块 (`webrtc/`)
- **WebRTCClient.kt** - WebRTC 连接管理核心，负责 PeerConnection 创建、SDP 交换、ICE 候选处理
- **ScreenCapturer.kt** - 屏幕采集封装，使用 MediaProjection API 采集屏幕并传递给 WebRTC
- **SignalingClient.kt** - 信令客户端，通过 WebSocket 与信令服务器通信，支持自动重连

#### 2. 设备发现模块 (`discovery/`)
- **DeviceDiscoveryManager.kt** - 使用 JmDNS 实现 mDNS 设备发现，广播和监听 `_opencast._tcp.local` 服务
- **DiscoveredDevice.kt** - 设备数据模型

#### 3. UI 模块 (`ui/`)
- **HomeScreen.kt** - 主页界面，显示发现的设备列表，支持自动发现和手动 IP 输入
- **CastingScreen.kt** - 投屏中界面，显示连接状态、延迟、分辨率、帧率等信息
- **theme/** - Material 3 深色主题配色

#### 4. 服务层 (`service/`)
- **ScreenCaptureService.kt** - 前台服务，管理屏幕采集生命周期，显示通知栏状态

### 信令协议

信令消息使用 JSON 格式通过 WebSocket 传输：

```json
// 设备注册
{ "type": "REGISTER", "deviceId": "abc123", "deviceName": "Pixel 8" }

// SDP Offer
{ "type": "OFFER", "sdp": "...", "targetDeviceId": "receiver1" }

// SDP Answer
{ "type": "ANSWER", "sdp": "...", "targetDeviceId": "sender1" }

// ICE 候选
{ "type": "ICE_CANDIDATE", "sdpMid": "0", "sdpMLineIndex": 0, "candidate": "...", "targetDeviceId": "sender1" }

// 断开连接
{ "type": "BYE", "targetDeviceId": "receiver1" }
```

## 构建和运行

### 前置要求

- Android Studio Hedgehog (2023.1.1) 或更高版本
- JDK 17
- Android SDK，compileSdk 34
- 一台 Android 7.0+ 设备或模拟器

### 构建步骤

1. 克隆项目到本地

2. 使用 Android Studio 打开项目根目录

3. 等待 Gradle 同步完成

4. 连接 Android 设备或启动模拟器

5. 点击 Run 运行应用

### 权限说明

应用需要以下权限：
- `INTERNET` - 网络通信
- `ACCESS_NETWORK_STATE` - 网络状态检测
- `ACCESS_WIFI_STATE` - WiFi 状态检测
- `CHANGE_WIFI_MULTICAST_STATE` - mDNS 多播
- `FOREGROUND_SERVICE` - 前台服务
- `FOREGROUND_SERVICE_MEDIA_PROJECTION` - 屏幕采集前台服务
- `MEDIA_PROJECTION` - 屏幕采集（运行时动态申请）
- `POST_NOTIFICATIONS` - 通知权限（Android 13+）

## 信令服务器部署

OpenCast 需要一个 WebSocket 信令服务器来协调连接。你可以使用以下 Node.js 代码快速搭建：

```javascript
// server.js - 简易信令服务器
const WebSocket = require('ws');

const PORT = 8443;
const wss = new WebSocket.Server({ port: PORT });

const clients = new Map();

wss.on('connection', (ws) => {
    let deviceId = null;

    ws.on('message', (data) => {
        const message = JSON.parse(data);

        switch (message.type) {
            case 'REGISTER':
                deviceId = message.deviceId;
                clients.set(deviceId, ws);
                ws.send(JSON.stringify({
                    type: 'REGISTER_ACK',
                    deviceId: deviceId
                }));
                console.log(`设备注册: ${deviceId} (${message.deviceName})`);
                break;

            case 'OFFER':
            case 'ANSWER':
            case 'ICE_CANDIDATE':
            case 'BYE':
                // 转发消息到目标设备
                const target = clients.get(message.targetDeviceId);
                if (target && target.readyState === WebSocket.OPEN) {
                    target.send(data.toString());
                }
                break;
        }
    });

    ws.on('close', () => {
        if (deviceId) {
            clients.delete(deviceId);
            console.log(`设备断开: ${deviceId}`);
        }
    });
});

console.log(`信令服务器已启动，端口: ${PORT}`);
```

### 部署步骤

1. 确保已安装 Node.js (v16+)

2. 安装依赖：
   ```bash
   npm install ws
   ```

3. 启动服务器：
   ```bash
   node server.js
   ```

4. 服务器默认监听 `ws://0.0.0.0:8443`

### 生产环境建议

- 使用 Nginx 反向代理 WebSocket
- 启用 WSS (WebSocket Secure) 加密传输
- 添加设备认证机制
- 实现心跳检测和超时清理
- 使用 PM2 或 systemd 管理进程

## 项目结构

```
opencast-android/
├── app/
│   ├── build.gradle.kts              # 应用构建配置
│   └── src/main/
│       ├── AndroidManifest.xml       # 应用清单
│       ├── java/com/opencast/app/
│       │   ├── MainActivity.kt       # 主 Activity
│       │   ├── OpenCastApplication.kt # Application 类
│       │   ├── di/
│       │   │   └── AppModule.kt      # Hilt 依赖注入模块
│       │   ├── ui/
│       │   │   ├── theme/            # Material 3 主题
│       │   │   ├── screen/           # 页面
│       │   │   └── viewmodel/        # ViewModel
│       │   ├── webrtc/               # WebRTC 核心模块
│       │   ├── discovery/            # 设备发现模块
│       │   └── service/              # 前台服务
│       └── res/                      # 资源文件
├── build.gradle.kts                  # 根构建配置
├── settings.gradle.kts               # 项目设置
└── gradle.properties                 # Gradle 属性
```

## 许可证

MIT License
