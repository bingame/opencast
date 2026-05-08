# OpenCast 信令服务器

## 简介

OpenCast 信令服务器负责协调发送端和接收端之间的 WebRTC 连接建立，包括设备注册、SDP 交换和 ICE 候选转发。

## 快速启动

```bash
# 安装依赖
npm install

# 启动服务器（默认端口 8443）
npm start

# 开发模式（文件变更自动重启）
npm run dev

# 自定义端口
PORT=9090 npm start
```

## Docker 部署

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY server.js .
EXPOSE 8443
CMD ["node", "server.js"]
```

```bash
# 构建镜像
docker build -t opencast-signaling .

# 运行容器
docker run -d -p 8443:8443 --name opencast-signal opencast-signaling
```

## 信令协议

### 消息格式

所有消息均为 JSON 格式，通过 WebSocket 传输。

### 消息类型

| 类型 | 方向 | 说明 |
|------|------|------|
| `register` | 客户端 → 服务器 | 注册设备 |
| `registered` | 服务器 → 客户端 | 注册确认 |
| `heartbeat` | 客户端 → 服务器 | 心跳 |
| `heartbeat_ack` | 服务器 → 客户端 | 心跳确认 |
| `device_list` | 服务器 → 客户端 | 设备列表 |
| `get_devices` | 客户端 → 服务器 | 请求设备列表 |
| `connect_request` | 客户端 → 服务器 | 请求连接 |
| `connect_response` | 客户端 → 服务器 | 响应连接 |
| `offer` | 客户端 → 服务器 | SDP Offer |
| `answer` | 客户端 → 服务器 | SDP Answer |
| `ice_candidate` | 客户端 → 服务器 | ICE 候选 |
| `bye` | 客户端 → 服务器 | 断开连接 |

### 消息示例

```json
// 注册设备
{
  "type": "register",
  "deviceId": "abc123",
  "deviceName": "我的 iPhone",
  "deviceType": "sender"
}

// 连接请求
{
  "type": "connect_request",
  "to": "def456"
}

// SDP Offer
{
  "type": "offer",
  "to": "def456",
  "sdp": "v=0\r\n..."
}

// ICE 候选
{
  "type": "ice_candidate",
  "to": "def456",
  "candidate": {
    "candidate": "candidate:...",
    "sdpMid": "0",
    "sdpMLineIndex": 0
  }
}
```

## 配置

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `PORT` | `8443` | 监听端口 |
| `MAX_CONNECTIONS` | `100` | 最大连接数 |

## 许可证

MIT License
