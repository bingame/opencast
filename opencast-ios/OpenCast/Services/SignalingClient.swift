// SignalingClient.swift - 信令客户端
// 通过 WebSocket 与信令服务器通信，处理 SDP 和 ICE 候选交换

import Foundation
import Combine

/// 信令客户端连接状态
enum SignalingState: String, CustomStringConvertible {
    case disconnected = "未连接"
    case connecting = "连接中"
    case connected = "已连接"
    case reconnecting = "重连中"
    case failed = "连接失败"

    var description: String { rawValue }
}

/// 信令客户端
/// 使用 URLSessionWebSocketTask 与信令服务器进行 WebSocket 通信
final class SignalingClient: ObservableObject {

    // MARK: - 发布属性

    /// 当前连接状态
    @Published private(set) var state: SignalingState = .disconnected

    /// 最后一次错误信息
    @Published var lastError: String?

    // MARK: - Combine 发布者

    /// 接收到的信令消息
    let messageReceived = PassthroughSubject<SignalingMessage, Never>()

    /// 连接状态变化
    let stateChanged = PassthroughSubject<SignalingState, Never>()

    // MARK: - 私有属性

    /// WebSocket 任务
    private var webSocketTask: URLSessionWebSocketTask?

    /// URL Session
    private let urlSession: URLSession

    /// 信令服务器地址
    private let serverURL: URL

    /// 设备 ID
    private let deviceId: String

    /// 设备名称
    private let deviceName: String

    /// 自动重连标志
    private var shouldReconnect: Bool = true

    /// 重连次数
    private var reconnectAttempts: Int = 0

    /// 最大重连次数
    private let maxReconnectAttempts: Int = 5

    /// 重连延迟（秒）
    private var reconnectDelay: Double = 1.0

    /// 最大重连延迟
    private let maxReconnectDelay: Double = 30.0

    /// 心跳定时器
    private var heartbeatTimer: Timer?

    /// 心跳间隔（秒）
    private let heartbeatInterval: TimeInterval = 30

    /// 接收消息的串行队列
    private let receiveQueue = DispatchQueue(label: "com.opencast.signaling.receive")

    /// 发送消息的串行队列
    private let sendQueue = DispatchQueue(label: "com.opencast.signaling.send")

    // MARK: - 初始化

    /// 初始化信令客户端
    /// - Parameters:
    ///   - serverURL: 信令服务器 WebSocket 地址
    ///   - deviceId: 设备唯一标识
    ///   - deviceName: 设备显示名称
    init(serverURL: URL, deviceId: String = UUID().uuidString, deviceName: String = "iPhone") {
        self.serverURL = serverURL
        self.deviceId = deviceId
        self.deviceName = deviceName

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: config)
    }

    deinit {
        disconnect()
    }

    // MARK: - 连接管理

    /// 连接到信令服务器
    func connect() {
        guard state != .connected else {
            print("[信令] 已连接，跳过重复连接")
            return
        }

        updateState(.connecting)
        print("[信令] 正在连接到服务器: \(serverURL.absoluteString)")

        let request = URLRequest(url: serverURL)
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        // 开始接收消息
        receiveMessage()

        // 监听连接完成
        webSocketTask?.completionHandler = { [weak self] error in
            if let error = error {
                print("[信令] WebSocket 连接错误: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                }
            }
            DispatchQueue.main.async {
                self?.handleDisconnection()
            }
        }

        // 发送注册消息
        sendRegistration()
    }

    /// 断开连接
    func disconnect() {
        shouldReconnect = false
        stopHeartbeat()

        // 发送注销消息
        let unregisterMsg = SignalingMessage.unregister(deviceId: deviceId)
        send(unregisterMsg)

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        updateState(.disconnected)
        print("[信令] 已断开连接")
    }

    /// 处理断开连接（可能触发重连）
    private func handleDisconnection() {
        guard shouldReconnect else { return }

        if reconnectAttempts < maxReconnectAttempts {
            updateState(.reconnecting)
            reconnectAttempts += 1

            // 指数退避
            let delay = min(reconnectDelay * Double(reconnectAttempts), maxReconnectDelay)
            print("[信令] 将在 \(delay) 秒后尝试第 \(reconnectAttempts) 次重连")

            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.connect()
            }
        } else {
            updateState(.failed)
            print("[信令] 已达到最大重连次数 (\(self.maxReconnectAttempts))")
        }
    }

    /// 更新连接状态
    private func updateState(_ newState: SignalingState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
            self?.stateChanged.send(newState)

            if newState == .connected {
                self?.reconnectAttempts = 0
                self?.reconnectDelay = 1.0
                self?.startHeartbeat()
            }
        }
    }

    // MARK: - 消息发送

    /// 发送信令消息
    /// - Parameter message: 信令消息
    func send(_ message: SignalingMessage) {
        sendQueue.async { [weak self] in
            guard let self = self, let webSocketTask = self.webSocketTask else {
                print("[信令] 未连接，无法发送消息")
                return
            }

            guard let jsonString = message.toJSONString() else {
                print("[信令] 消息序列化失败")
                return
            }

            let task = webSocketTask.send(URLSessionWebSocketTask.Message.string(jsonString)) { error in
                if let error = error {
                    print("[信令] 发送消息失败: \(error.localizedDescription)")
                } else {
                    print("[信令] 消息已发送: \(message.typeValue)")
                }
            }
            task.resume()
        }
    }

    /// 发送设备注册消息
    private func sendRegistration() {
        let registerMsg = SignalingMessage.register(
            deviceId: deviceId,
            deviceName: deviceName,
            deviceType: "ios"
        )
        send(registerMsg)
    }

    /// 发送连接请求
    /// - Parameter targetDeviceId: 目标设备 ID
    func sendConnectRequest(to targetDeviceId: String) {
        let message = SignalingMessage.connectRequest(
            fromDeviceId: deviceId,
            toDeviceId: targetDeviceId
        )
        send(message)
    }

    /// 发送 SDP Offer
    /// - Parameters:
    ///   - sdp: SDP 内容
    ///   - sessionId: 会话 ID
    func sendOffer(sdp: String, sessionId: String) {
        let message = SignalingMessage.offer(sdp: sdp, sessionId: sessionId)
        send(message)
    }

    /// 发送 SDP Answer
    /// - Parameters:
    ///   - sdp: SDP 内容
    ///   - sessionId: 会话 ID
    func sendAnswer(sdp: String, sessionId: String) {
        let message = SignalingMessage.answer(sdp: sdp, sessionId: sessionId)
        send(message)
    }

    /// 发送 ICE 候选
    /// - Parameters:
    ///   - sdp: ICE 候选 SDP
    ///   - sdpMid: SDP 媒体标识
    ///   - sdpMLineIndex: SDP 媒体行索引
    ///   - sessionId: 会话 ID
    func sendICECandidate(sdp: String, sdpMid: String, sdpMLineIndex: Int32, sessionId: String) {
        let message = SignalingMessage.iceCandidate(
            sdp: sdp,
            sdpMid: sdpMid,
            sdpMLineIndex: sdpMLineIndex,
            sessionId: sessionId
        )
        send(message)
    }

    /// 发送断开连接消息
    /// - Parameter sessionId: 会话 ID
    func sendDisconnect(sessionId: String) {
        let message = SignalingMessage.disconnect(sessionId: sessionId)
        send(message)
    }

    // MARK: - 消息接收

    /// 接收消息（递归调用保持持续接收）
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleReceivedMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleReceivedMessage(text)
                    }
                @unknown default:
                    break
                }
                // 继续接收下一条消息
                self?.receiveMessage()

            case .failure(let error):
                print("[信令] 接收消息失败: \(error.localizedDescription)")
            }
        }
    }

    /// 处理接收到的消息
    /// - Parameter text: JSON 字符串
    private func handleReceivedMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        guard let message = SignalingMessage.fromJSON(data) else {
            print("[信令] 消息解析失败: \(text)")
            return
        }

        print("[信令] 收到消息: \(message.typeValue)")
        messageReceived.send(message)
    }

    // MARK: - 心跳

    /// 启动心跳定时器
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }

    /// 停止心跳定时器
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /// 发送心跳消息
    private func sendHeartbeat() {
        let message = SignalingMessage.heartbeat(deviceId: deviceId)
        send(message)
    }
}
