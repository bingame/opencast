/**
 * OpenCast 信令服务器
 * 
 * 职责：
 * 1. 维护在线设备列表
 * 2. 转发 SDP Offer/Answer
 * 3. 转发 ICE 候选信息
 * 4. 心跳检测和连接状态管理
 * 
 * 信令协议：
 * - REGISTER:     { type: "register", deviceId, deviceName, deviceType: "sender"|"receiver" }
 * - UNREGISTER:   { type: "unregister", deviceId }
 * - DEVICE_LIST:  { type: "device_list", devices: [...] }
 * - CONNECT_REQ:  { type: "connect_request", from, to }
 * - CONNECT_RESP: { type: "connect_response", from, to, accepted }
 * - OFFER:        { type: "offer", from, to, sdp }
 * - ANSWER:       { type: "answer", from, to, sdp }
 * - ICE:          { type: "ice_candidate", from, to, candidate }
 * - BYE:          { type: "bye", from, to }
 * - HEARTBEAT:    { type: "heartbeat", deviceId }
 */

const { WebSocketServer } = require('ws');
const { v4: uuidv4 } = require('uuid');

// ========== 配置 ==========
const PORT = process.env.PORT || 8443;
const HEARTBEAT_INTERVAL = 30000;    // 心跳间隔 30 秒
const HEARTBEAT_TIMEOUT = 90000;     // 心跳超时 90 秒
const MAX_CONNECTIONS = 100;         // 最大连接数

// ========== 全局状态 ==========
const wss = new WebSocketServer({ port: PORT });
const devices = new Map();           // deviceId -> { ws, deviceName, deviceType, lastHeartbeat }
const connectionPairs = new Map();   // "senderId:receiverId" -> { senderWs, receiverWs }

console.log(`[OpenCast] 信令服务器启动，端口: ${PORT}`);

// ========== 工具函数 ==========

/**
 * 生成设备列表消息
 */
function getDeviceListMessage(excludeId = null) {
  const deviceList = [];
  for (const [id, info] of devices) {
    if (id !== excludeId && info.ws.readyState === 1) {
      deviceList.push({
        deviceId: id,
        deviceName: info.deviceName,
        deviceType: info.deviceType
      });
    }
  }
  return { type: 'device_list', devices: deviceList };
}

/**
 * 广播设备列表给所有客户端
 */
function broadcastDeviceList() {
  const message = JSON.stringify(getDeviceListMessage());
  for (const [id, info] of devices) {
    if (info.ws.readyState === 1) {
      info.ws.send(message);
    }
  }
}

/**
 * 向指定设备发送消息
 */
function sendToDevice(deviceId, message) {
  const device = devices.get(deviceId);
  if (device && device.ws.readyState === 1) {
    device.ws.send(JSON.stringify(message));
    return true;
  }
  console.log(`[警告] 设备 ${deviceId} 不在线或连接已断开`);
  return false;
}

/**
 * 清理断开的设备
 */
function cleanupDevice(deviceId) {
  const device = devices.get(deviceId);
  if (device) {
    // 清理该设备相关的连接对
    for (const [key, pair] of connectionPairs) {
      if (key.includes(deviceId)) {
        const otherId = key.split(':').find(id => id !== deviceId);
        sendToDevice(otherId, {
          type: 'bye',
          from: deviceId,
          reason: 'device_disconnected'
        });
        connectionPairs.delete(key);
      }
    }
    devices.delete(deviceId);
    console.log(`[断开] 设备 ${device.deviceName} (${deviceId}) 已断开`);
    broadcastDeviceList();
  }
}

// ========== 心跳检测 ==========
const heartbeatTimer = setInterval(() => {
  const now = Date.now();
  for (const [id, info] of devices) {
    if (now - info.lastHeartbeat > HEARTBEAT_TIMEOUT) {
      console.log(`[超时] 设备 ${info.deviceName} (${id}) 心跳超时，断开连接`);
      info.ws.terminate();
      cleanupDevice(id);
    }
  }
}, HEARTBEAT_INTERVAL);

// ========== WebSocket 连接处理 ==========
wss.on('connection', (ws, req) => {
  // 限制最大连接数
  if (devices.size >= MAX_CONNECTIONS) {
    ws.send(JSON.stringify({ type: 'error', message: '服务器已满，请稍后重试' }));
    ws.close();
    return;
  }

  const clientIp = req.socket.remoteAddress;
  console.log(`[连接] 新连接来自 ${clientIp}，当前在线: ${devices.size}`);

  let deviceId = null;

  ws.on('message', (data) => {
    let message;
    try {
      message = JSON.parse(data);
    } catch (e) {
      console.log(`[错误] 无法解析消息: ${data}`);
      return;
    }

    // 更新心跳时间
    if (deviceId) {
      const device = devices.get(deviceId);
      if (device) {
        device.lastHeartbeat = Date.now();
      }
    }

    switch (message.type) {
      // ===== 设备注册 =====
      case 'register': {
        deviceId = message.deviceId || uuidv4();
        const deviceName = message.deviceName || `设备-${deviceId.slice(0, 6)}`;
        const deviceType = message.deviceType || 'sender';

        devices.set(deviceId, {
          ws,
          deviceName,
          deviceType,
          lastHeartbeat: Date.now()
        });

        console.log(`[注册] ${deviceType === 'sender' ? '发送端' : '接收端'}: ${deviceName} (${deviceId})`);

        // 发送注册确认
        ws.send(JSON.stringify({
          type: 'registered',
          deviceId,
          deviceName,
          deviceType
        }));

        // 广播设备列表
        broadcastDeviceList();
        break;
      }

      // ===== 心跳 =====
      case 'heartbeat': {
        // 心跳时间已在上面更新
        ws.send(JSON.stringify({ type: 'heartbeat_ack', timestamp: Date.now() }));
        break;
      }

      // ===== 连接请求 =====
      case 'connect_request': {
        const { to } = message;
        console.log(`[请求] ${deviceId} 请求连接到 ${to}`);

        // 转发连接请求给目标设备
        sendToDevice(to, {
          type: 'connect_request',
          from: deviceId,
          fromName: devices.get(deviceId)?.deviceName
        });
        break;
      }

      // ===== 连接响应 =====
      case 'connect_response': {
        const { to, accepted } = message;
        console.log(`[响应] ${deviceId} ${accepted ? '接受' : '拒绝'}了来自 ${to} 的连接`);

        sendToDevice(to, {
          type: 'connect_response',
          from: deviceId,
          accepted
        });

        if (accepted) {
          // 记录连接对
          const senderId = devices.get(deviceId)?.deviceType === 'sender' ? deviceId : to;
          const receiverId = senderId === deviceId ? to : deviceId;
          connectionPairs.set(`${senderId}:${receiverId}`, {
            senderWs: devices.get(senderId)?.ws,
            receiverWs: devices.get(receiverId)?.ws
          });
        }
        break;
      }

      // ===== SDP Offer =====
      case 'offer': {
        const { to, sdp } = message;
        console.log(`[SDP] Offer: ${deviceId} -> ${to}`);

        sendToDevice(to, {
          type: 'offer',
          from: deviceId,
          sdp
        });
        break;
      }

      // ===== SDP Answer =====
      case 'answer': {
        const { to, sdp } = message;
        console.log(`[SDP] Answer: ${deviceId} -> ${to}`);

        sendToDevice(to, {
          type: 'answer',
          from: deviceId,
          sdp
        });
        break;
      }

      // ===== ICE 候选 =====
      case 'ice_candidate': {
        const { to, candidate } = message;
        sendToDevice(to, {
          type: 'ice_candidate',
          from: deviceId,
          candidate
        });
        break;
      }

      // ===== 断开连接 =====
      case 'bye': {
        const { to, reason } = message;
        console.log(`[断开] ${deviceId} -> ${to}, 原因: ${reason || '用户主动断开'}`);

        sendToDevice(to, {
          type: 'bye',
          from: deviceId,
          reason
        });

        // 清理连接对
        for (const [key] of connectionPairs) {
          if (key.includes(deviceId)) {
            connectionPairs.delete(key);
          }
        }
        break;
      }

      // ===== 请求设备列表 =====
      case 'get_devices': {
        ws.send(JSON.stringify(getDeviceListMessage(deviceId)));
        break;
      }

      default:
        console.log(`[未知] 收到未知消息类型: ${message.type}`);
    }
  });

  ws.on('close', (code, reason) => {
    console.log(`[关闭] ${deviceId || '未注册'} 断开连接，代码: ${code}`);
    if (deviceId) {
      cleanupDevice(deviceId);
    }
  });

  ws.on('error', (error) => {
    console.log(`[错误] ${deviceId || '未注册'} 连接错误: ${error.message}`);
    if (deviceId) {
      cleanupDevice(deviceId);
    }
  });
});

// ========== 优雅关闭 ==========
process.on('SIGINT', () => {
  console.log('\n[关闭] 正在关闭信令服务器...');
  clearInterval(heartbeatTimer);
  
  // 通知所有客户端服务器即将关闭
  for (const [id, info] of devices) {
    if (info.ws.readyState === 1) {
      info.ws.send(JSON.stringify({ type: 'server_shutdown' }));
    }
  }
  
  wss.close(() => {
    console.log('[关闭] 信令服务器已关闭');
    process.exit(0);
  });

  // 5 秒后强制关闭
  setTimeout(() => {
    console.log('[关闭] 强制关闭');
    process.exit(0);
  }, 5000);
});

console.log(`[OpenCast] 信令服务器就绪，监听端口: ${PORT}`);
console.log(`[OpenCast] 最大连接数: ${MAX_CONNECTIONS}`);
console.log(`[OpenCast] 心跳间隔: ${HEARTBEAT_INTERVAL / 1000}s, 超时: ${HEARTBEAT_TIMEOUT / 1000}s`);
