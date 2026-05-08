// CastingViewModel.swift - 投屏控制视图模型
// 管理 WebRTC 连接状态、投屏开始/停止和连接信息

import Foundation
import Combine
import SwiftUI
import ReplayKit
import CoreMedia
import UIKit

/// 投屏状态
enum CastingStatus: String, CustomStringConvertible {
    /// 空闲
    case idle = "空闲"
    /// 正在连接
    case connecting = "连接中"
    /// 已连接
    case connected = "已连接"
    /// 投屏中
    case casting = "投屏中"
    /// 暂停
    case paused = "已暂停"
    /// 断开中
    case disconnecting = "断开中"
    /// 错误
    case error = "错误"

    var description: String { rawValue }

    /// 是否正在投屏
    var isCasting: Bool {
        self == .casting
    }

    /// 是否可以操作
    var canOperate: Bool {
        self == .idle || self == .connected || self == .casting || self == .paused
    }
}

/// 投屏控制视图模型
/// 管理完整的投屏生命周期：连接建立 -> ReplayKit 启动 -> 视频流传输 -> 断开
@MainActor
final class CastingViewModel: ObservableObject {

    // MARK: - 发布属性

    /// 投屏状态
    @Published private(set) var status: CastingStatus = .idle

    /// 当前连接的设备
    @Published var connectedDevice: DiscoveredDevice?

    /// WebRTC 连接状态
    @Published private(set) var connectionState: WebRTCConnectionState = .new

    /// 连接延迟（毫秒）
    @Published private(set) var latency: Int = 0

    /// 视频分辨率
    @Published private(set) var videoResolution: CGSize = .zero

    /// 当前帧率
    @Published private(set) var fps: Int = 0

    /// 投屏时长
    @Published private(set) var castingDuration: TimeInterval = 0

    /// 错误信息
    @Published var errorMessage: String?

    /// 是否显示错误
    @Published var showError: Bool = false

    /// 是否显示连接成功提示
    @Published var showConnectedAlert: Bool = false

    /// 格式化的投屏时长
    var formattedDuration: String {
        let hours = Int(castingDuration) / 3600
        let minutes = (Int(castingDuration) % 3600) / 60
        let seconds = Int(castingDuration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// 格式化的分辨率
    var formattedResolution: String {
        if videoResolution == .zero {
            return "等待视频流..."
        }
        return "\(Int(videoResolution.width)) x \(Int(videoResolution.height))"
    }

    /// 格式化的延迟
    var formattedLatency: String {
        if latency == 0 {
            return "--"
        }
        return "\(latency) ms"
    }

    // MARK: - 私有属性

    /// WebRTC 客户端
    private var webRTCClient: WebRTCClient?

    /// 信令客户端
    private var signalingClient: SignalingClient?

    /// ReplayKit 屏幕录制控制器
    private var broadcastPicker: RPSystemBroadcastPickerView?

    /// 投屏计时器
    private var castingTimer: Timer?

    /// 投屏开始时间
    private var castingStartTime: Date?

    /// 当前会话 ID
    private var sessionId: String = ""

    /// Combine 取消集合
    private var cancellables = Set<AnyCancellable>()

    /// App Group 标识（用于与 Broadcast Extension 共享数据）
    private let appGroupIdentifier = "group.com.opencast.app"

    // MARK: - 初始化

    init() {
        // 监听来自 Broadcast Extension 的通知
        setupBroadcastNotifications()
    }

    deinit {
        stopCasting()
        removeBroadcastNotifications()
    }

    // MARK: - 投屏控制

    /// 开始投屏到指定设备
    /// - Parameter device: 目标设备
    func startCasting(to device: DiscoveredDevice) {
        print("[投屏] 开始连接到设备: \(device.name)")

        connectedDevice = device
        status = .connecting
        errorMessage = nil

        // 创建会话 ID
        sessionId = UUID().uuidString

        // 1. 创建 WebRTC 客户端
        setupWebRTCClient()

        // 2. 创建信令客户端并连接
        setupSignalingClient(for: device)

        // 3. 创建 PeerConnection
        webRTCClient?.createPeerConnection()

        // 4. 创建本地视频轨道
        webRTCClient?.createLocalVideoTrack()
    }

    /// 停止投屏
    func stopCasting() {
        print("[投屏] 停止投屏")

        status = .disconnecting

        // 停止计时器
        stopCastingTimer()

        // 发送断开消息
        if !sessionId.isEmpty {
            signalingClient?.sendDisconnect(sessionId: sessionId)
        }

        // 关闭信令连接
        signalingClient?.disconnect()
        signalingClient = nil

        // 关闭 WebRTC 连接
        webRTCClient?.close()
        webRTCClient = nil

        // 重置状态
        connectedDevice = nil
        connectionState = .new
        latency = 0
        videoResolution = .zero
        fps = 0
        castingDuration = 0
        sessionId = ""

        status = .idle
        print("[投屏] 投屏已停止")
    }

    /// 暂停投屏
    func pauseCasting() {
        guard status == .casting else { return }
        status = .paused
        stopCastingTimer()
        print("[投屏] 投屏已暂停")
    }

    /// 恢复投屏
    func resumeCasting() {
        guard status == .paused else { return }
        status = .casting
        startCastingTimer()
        print("[投屏] 投屏已恢复")
    }

    // MARK: - ReplayKit 集成

    /// 显示系统投屏选择器
    /// - Parameter anchorView: 锚点视图（用于 iPad 弹出位置）
    func showBroadcastPicker(from anchorView: UIView? = nil) {
        // 使用 RPSystemBroadcastPickerView 显示系统投屏选择器
        // 注意：Broadcast Extension 需要在 Xcode 中正确配置
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        picker.preferredExtension = "com.opencast.app.BroadcastExtension"

        // 查找并触发按钮点击
        if let button = picker.subviews.first(where: { $0 is UIButton }) as? UIButton {
            button.sendActions(for: .touchUpInside)
        }

        self.broadcastPicker = picker
        print("[投屏] 已显示系统投屏选择器")
    }

    // MARK: - 私有方法 - 设置

    /// 设置 WebRTC 客户端
    private func setupWebRTCClient() {
        // 配置 ICE 服务器（STUN/TURN）
        let iceServers = [
            "stun:stun.l.google.com:19302",
            "stun:stun1.l.google.com:19302"
        ]

        webRTCClient = WebRTCClient(
            iceServers: iceServers,
            sessionId: sessionId
        )

        // 绑定 WebRTC 状态
        webRTCClient?.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
                self?.updateStatusFromConnection(state)
            }
            .store(in: &cancellables)

        // 绑定视频分辨率
        webRTCClient?.$videoResolution
            .receive(on: DispatchQueue.main)
            .sink { [weak self] resolution in
                self?.videoResolution = resolution
            }
            .store(in: &cancellables)

        // 绑定帧率
        webRTCClient?.$currentFPS
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fps in
                self?.fps = fps
            }
            .store(in: &cancellables)

        // 监听 ICE 候选
        webRTCClient?.onICECandidate
            .sink { [weak self] message in
                if case .iceCandidate(let sdp, let sdpMid, let sdpMLineIndex, let sessionId) = message {
                    self?.signalingClient?.sendICECandidate(
                        sdp: sdp,
                        sdpMid: sdpMid,
                        sdpMLineIndex: sdpMLineIndex,
                        sessionId: sessionId
                    )
                }
            }
            .store(in: &cancellables)
    }

    /// 设置信令客户端
    /// - Parameter device: 目标设备
    private func setupSignalingClient(for device: DiscoveredDevice) {
        guard let url = URL(string: device.signalingURL) else {
            handleError("无效的信令服务器地址")
            return
        }

        signalingClient = SignalingClient(
            serverURL: url,
            deviceName: UIDevice.current.name
        )

        // 绑定信令状态
        signalingClient?.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                print("[投屏] 信令状态: \(state.description)")
            }
            .store(in: &cancellables)

        // 监听接收到的消息
        signalingClient?.messageReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleSignalingMessage(message)
            }
            .store(in: &cancellables)

        // 连接信令服务器
        signalingClient?.connect()
    }

    /// 处理信令消息
    /// - Parameter message: 信令消息
    private func handleSignalingMessage(_ message: SignalingMessage) {
        switch message {
        case .answer(let sdp, _):
            // 收到远端 Answer
            print("[投屏] 收到 SDP Answer")
            webRTCClient?.setRemoteAnswer(sdp: sdp)

        case .iceCandidate(let sdp, let sdpMid, let sdpMLineIndex, _):
            // 收到远端 ICE 候选
            webRTCClient?.addICECandidate(
                sdp: sdp,
                sdpMid: sdpMid,
                sdpMLineIndex: sdpMLineIndex
            )

        case .connectResponse(let accepted, _, _):
            if accepted {
                print("[投屏] 连接请求被接受")
                // 创建并发送 Offer（异步，避免主线程死锁）
                webRTCClient?.createOffer { [weak self] offerSDP in
                    guard let self = self, let offerSDP = offerSDP else {
                        self?.handleError("创建 SDP Offer 失败")
                        return
                    }
                    self.signalingClient?.sendOffer(sdp: offerSDP, sessionId: self.sessionId)
                }
            } else {
                handleError("对方拒绝了连接请求")
            }

        case .error(_, let message):
            handleError(message)

        default:
            print("[投屏] 收到未处理的消息类型")
            break
        }
    }

    /// 根据连接状态更新投屏状态
    /// - Parameter state: WebRTC 连接状态
    private func updateStatusFromConnection(_ state: WebRTCConnectionState) {
        switch state {
        case .connected:
            if status == .connecting {
                status = .connected
                showConnectedAlert = true
            }
        case .failed:
            handleError("WebRTC 连接失败")
        case .disconnected:
            if status == .casting {
                handleError("连接已断开")
            }
        default:
            break
        }
    }

    // MARK: - 投屏计时

    /// 启动投屏计时器
    private func startCastingTimer() {
        castingStartTime = Date()
        castingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.castingStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            Task { @MainActor in
                self.castingDuration = elapsed
            }
        }
    }

    /// 停止投屏计时器
    private func stopCastingTimer() {
        castingTimer?.invalidate()
        castingTimer = nil
        castingStartTime = nil
    }

    // MARK: - Broadcast Extension 通知

    /// Darwin 通知回调引用（需要保持强引用以防止被释放）
    private var darwinObserver: DarwinNotificationObserver?

    /// 设置 Broadcast Extension 通知监听
    /// 使用 Darwin Notification（CFNotificationCenter）实现跨进程通信
    private func setupBroadcastNotifications() {
        darwinObserver = DarwinNotificationObserver()

        // 监听广播开始
        darwinObserver?.observe(name: "OpenCastBroadcastStarted") { [weak self] in
            Task { @MainActor in
                print("[投屏] Broadcast Extension 已启动")
                self?.status = .casting
                self?.startCastingTimer()
            }
        }

        // 监听广播停止
        darwinObserver?.observe(name: "OpenCastBroadcastStopped") { [weak self] in
            Task { @MainActor in
                print("[投屏] Broadcast Extension 已停止")
                self?.stopCasting()
            }
        }

        // 监听广播错误
        darwinObserver?.observe(name: "OpenCastBroadcastError") { [weak self] in
            Task { @MainActor in
                // 从共享 UserDefaults 读取错误信息
                if let defaults = UserDefaults(suiteName: "group.com.opencast.app"),
                   let errorInfo = defaults.dictionary(forKey: "notification_OpenCastBroadcastError"),
                   let errorMessage = errorInfo["error"] as? String {
                    self?.handleError("广播错误: \(errorMessage)")
                } else {
                    self?.handleError("广播发生未知错误")
                }
            }
        }

        // 监听视频帧可用
        darwinObserver?.observe(name: "OpenCastVideoFrame") { [weak self] in
            Task { @MainActor in
                self?.handleIncomingVideoFrame()
            }
        }
    }

    /// 移除通知监听
    private func removeBroadcastNotifications() {
        darwinObserver = nil
    }

    /// 处理来自 Broadcast Extension 的视频帧
    /// 通过 App Group 共享容器获取帧数据
    private func handleIncomingVideoFrame() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return }

        let frameDir = containerURL.appendingPathComponent("FrameBuffer", isDirectory: true)

        // 读取最新的帧元信息
        let metaURL = frameDir.appendingPathComponent("latest_frame.meta")
        guard let metaString = try? String(contentsOf: metaURL, encoding: .utf8) else { return }

        let parts = metaString.split(separator: ",").map(String.init)
        guard parts.count >= 3 else { return }

        let width = Int(parts[0]) ?? 0
        let height = Int(parts[1]) ?? 0
        let timestampSeconds = Double(parts[2]) ?? 0

        // 注意：实际生产环境中，应使用 IOSurface 或共享内存传递像素数据
        // 此处为简化实现，仅记录帧信息
        // 实际像素数据传输需要使用更高效的 IPC 机制
        print("[投屏] 收到视频帧: \(width)x\(height), 时间戳: \(timestampSeconds)")
    }

    // MARK: - 错误处理

    /// 处理错误
    /// - Parameter message: 错误信息
    private func handleError(_ message: String) {
        print("[投屏] 错误: \(message)")
        errorMessage = message
        showError = true

        if status != .idle {
            status = .error
        }
    }

    /// 清除错误
    func clearError() {
        errorMessage = nil
        showError = false
    }
}
