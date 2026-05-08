# OpenCast - iOS 投屏应用

基于 Swift + SwiftUI + WebRTC 技术栈的 iOS 屏幕投屏应用，支持通过 Bonjour 发现局域网设备，使用 WebRTC 进行低延迟视频传输。

## 技术架构

### 整体架构

```
┌─────────────────────────────────────────────────────┐
│                    OpenCast App                      │
│                                                      │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  Views   │  │  ViewModels  │  │   Services    │  │
│  │          │  │              │  │               │  │
│  │ HomeView │──│ DeviceListVM │──│ DeviceDiscovery│ │
│  │ DeviceLV │  │ CastingVM    │──│ WebRTCClient  │  │
│  │ CastingV │  │              │  │ SignalingClient│ │
│  │ Settings │  │              │  │               │  │
│  └──────────┘  └──────────────┘  └───────────────┘  │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │              Models                          │    │
│  │  DiscoveredDevice / SignalingMessage         │    │
│  └──────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
          │                    │
          │ WebSocket          │ mDNS/Bonjour
          ▼                    ▼
┌──────────────────┐  ┌──────────────────┐
│  信令服务器       │  │  接收端设备       │
│  (Node.js/Go)    │  │  (TV/PC/投影仪)  │
└──────────────────┘  └──────────────────┘

┌─────────────────────────────────────────────────────┐
│           Broadcast Extension (ReplayKit)            │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │  SampleHandler                               │    │
│  │  - 接收屏幕录制视频帧                         │    │
│  │  - CMSampleBuffer → CVPixelBuffer 转换       │    │
│  │  - 通过 App Group 共享数据给主 App            │    │
│  └──────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### 技术栈

| 组件 | 技术 | 说明 |
|------|------|------|
| UI 框架 | SwiftUI | 声明式 UI 构建 |
| 响应式编程 | Combine | @Published / PassthroughSubject / CurrentValueSubject |
| 视频传输 | GoogleWebRTC | WebRTC 核心库，支持 H.264/VP8 编码 |
| 屏幕录制 | ReplayKit | 系统级屏幕录制框架 |
| 设备发现 | Bonjour (Network.framework) | mDNS 局域网设备发现 |
| 信令通信 | URLSessionWebSocketTask | WebSocket 信令通道 |
| 跨进程通信 | App Group + Darwin Notification | 主 App 与 Extension 数据共享 |

### 项目结构

```
opencast-ios/
├── OpenCast.xcodeproj/          # Xcode 项目文件
├── OpenCast/                    # 主应用目标
│   ├── App/                     # 应用入口
│   │   ├── OpenCastApp.swift    # @main 入口
│   │   └── ContentView.swift    # 根视图
│   ├── Models/                  # 数据模型
│   │   ├── DiscoveredDevice.swift    # 设备模型
│   │   └── SignalingMessage.swift    # 信令消息
│   ├── Services/                # 核心服务
│   │   ├── WebRTCClient.swift        # WebRTC 连接管理
│   │   ├── SignalingClient.swift     # WebSocket 信令
│   │   └── DeviceDiscoveryService.swift  # Bonjour 发现
│   ├── Views/                   # SwiftUI 视图
│   │   ├── HomeView.swift             # 主页导航
│   │   ├── DeviceListView.swift       # 设备列表
│   │   ├── CastingView.swift          # 投屏状态
│   │   └── SettingsView.swift         # 设置页面
│   ├── ViewModels/              # 视图模型
│   │   ├── DeviceListViewModel.swift  # 设备列表逻辑
│   │   └── CastingViewModel.swift     # 投屏控制逻辑
│   ├── Broadcast/               # Broadcast Extension 接口
│   │   └── SampleHandler.swift        # 常量定义
│   └── Resources/               # 资源文件
│       └── Assets.xcassets/
├── OpenCastBroadcastExtension/  # Broadcast Extension 目标
│   ├── Info.plist               # Extension 配置
│   └── SampleHandler.swift      # 屏幕录制处理
├── Package.swift                # SPM 依赖管理
└── README.md
```

## 构建和运行

### 前置要求

- macOS 13.0+ (Xcode 15+)
- iOS 14.0+ 部署目标
- Xcode 15+

### 构建步骤

1. **克隆项目**

```bash
git clone https://github.com/your-repo/opencast-ios.git
cd opencast-ios
```

2. **打开 Xcode 项目**

```bash
open OpenCast.xcodeproj
```

3. **配置签名**

- 在 Xcode 中选择你的开发团队（Targets -> OpenCast -> Signing & Capabilities）
- 同样为 OpenCastBroadcastExtension 配置签名

4. **配置 App Group**

- 在主 App Target 中添加 App Group capability: `group.com.opencast.app`
- 在 Broadcast Extension Target 中添加相同的 App Group

5. **配置 Broadcast Extension**

- 确保主 App 的 Info.plist 中包含 Broadcast Extension 的引用
- 在 `Targets -> OpenCast -> General -> Embedded Binaries` 中添加 OpenCastBroadcastExtension

6. **配置依赖**

```bash
# 如果使用 CocoaPods（备选方案）
pod install

# 或使用 Swift Package Manager（推荐）
# Xcode 会自动解析 Package.swift 中的依赖
```

7. **构建运行**

- 选择目标设备或模拟器
- 注意：ReplayKit Broadcast Extension 在模拟器上功能受限，建议使用真机测试
- 按 `Cmd + R` 运行

### 关键配置项

#### Info.plist 权限

在主 App 的 Info.plist 中添加：

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>OpenCast 需要访问本地网络以发现同一局域网内的接收端设备</string>

<key>NSBonjourServices</key>
<array>
    <string>_opencast._tcp</string>
</array>

<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>
```

#### Capability 配置

两个 Target 都需要添加以下 Capabilities：

1. **App Groups**: `group.com.opencast.app`
2. **Local Network Access** (iOS 14+)

## 信令服务器

OpenCast 需要一个 WebSocket 信令服务器来协调 WebRTC 连接。以下是部署说明。

### 信令协议

信令消息格式（JSON）：

```json
// 设备注册
{
  "type": "register",
  "deviceId": "uuid",
  "deviceName": "iPhone",
  "deviceType": "ios"
}

// 连接请求
{
  "type": "connectRequest",
  "fromDeviceId": "sender-uuid",
  "toDeviceId": "receiver-uuid"
}

// SDP Offer
{
  "type": "offer",
  "sdp": "v=0\r\n...",
  "sessionId": "session-uuid"
}

// SDP Answer
{
  "type": "answer",
  "sdp": "v=0\r\n...",
  "sessionId": "session-uuid"
}

// ICE Candidate
{
  "type": "iceCandidate",
  "sdp": "candidate:...",
  "sdpMid": "0",
  "sdpMLineIndex": 0,
  "sessionId": "session-uuid"
}
```

### 参考实现（Node.js）

```javascript
// server.js - 简易信令服务器
const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 });

const clients = new Map();

wss.on('connection', (ws) => {
  ws.on('message', (data) => {
    const message = JSON.parse(data);

    switch (message.type) {
      case 'register':
        clients.set(message.deviceId, ws);
        ws.deviceId = message.deviceId;
        break;

      case 'connectRequest':
        const target = clients.get(message.toDeviceId);
        if (target) {
          target.send(JSON.stringify(message));
        }
        break;

      case 'offer':
      case 'answer':
      case 'iceCandidate':
        // 转发给会话对端
        for (const [id, client] of clients) {
          if (client !== ws && client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify(message));
          }
        }
        break;
    }
  });

  ws.on('close', () => {
    if (ws.deviceId) {
      clients.delete(ws.deviceId);
    }
  });
});

console.log('信令服务器运行在 ws://0.0.0.0:8080');
```

### 部署

```bash
# 安装依赖
npm install ws

# 启动服务器
node server.js

# 或使用 PM2 守护进程
pm2 start server.js --name opencast-signaling
```

## 核心功能说明

### WebRTC 连接流程

```
发送端 (iOS)                  信令服务器              接收端
    │                            │                     │
    │──── 注册 ──────────────────>│                     │
    │                            │<──── 注册 ──────────│
    │                            │                     │
    │──── 连接请求 ──────────────>│──── 连接请求 ──────>│
    │                            │<──── 连接响应 ──────│
    │<─── 连接响应 ──────────────│                     │
    │                            │                     │
    │──── SDP Offer ────────────>│──── SDP Offer ─────>│
    │                            │<──── SDP Answer ────│
    │<─── SDP Answer ────────────│                     │
    │                            │                     │
    │<═══════ ICE 候选交换 ══════>│<═══════ ICE 候选交换 ═>│
    │                            │                     │
    │<══════════════ WebRTC P2P 媒体流 ═══════════════>│
```

### 屏幕录制流程

```
系统 ReplayKit                Broadcast Extension       主 App
    │                              │                     │
    │──── 启动录制 ────────────────>│                     │
    │                              │── 通知广播开始 ─────>│
    │                              │                     │
    │──── CMSampleBuffer ─────────>│                     │
    │                              │── CVPixelBuffer ───>│
    │                              │                     │
    │                              │   WebRTCClient      │
    │                              │   pushVideoFrame()  │
    │                              │                     │
    │──── 停止录制 ────────────────>│                     │
    │                              │── 通知广播结束 ─────>│
```

## 注意事项

1. **真机测试**: ReplayKit Broadcast Extension 在模拟器上无法完整工作，必须使用真机测试
2. **网络环境**: 确保发送端和接收端在同一局域网内
3. **Bonjour 权限**: iOS 14+ 需要用户授权本地网络访问权限
4. **App Group**: 主 App 和 Broadcast Extension 必须配置相同的 App Group
5. **Bundle Identifier**: Broadcast Extension 的 Bundle ID 必须是主 App Bundle ID 的扩展（如 `com.opencast.app.BroadcastExtension`）

## 许可证

MIT License
