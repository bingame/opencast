// WebRTCClient.swift - WebRTC 客户端核心
// 管理 WebRTC PeerConnection、SDP 协商、ICE 候选交换和媒体轨道

import Foundation
import Combine
import AVFoundation
import CoreMedia
import GoogleWebRTC

/// WebRTC 连接状态
enum WebRTCConnectionState: String, CustomStringConvertible {
    case new = "新建"
    case connecting = "连接中"
    case connected = "已连接"
    case disconnected = "已断开"
    case failed = "连接失败"
    case closed = "已关闭"

    var description: String { rawValue }
}

/// WebRTC 客户端核心类
/// 负责 WebRTC 连接的完整生命周期管理
final class WebRTCClient: NSObject, ObservableObject {

    // MARK: - 发布属性

    /// 当前连接状态
    @Published private(set) var connectionState: WebRTCConnectionState = .new

    /// 本地 SDP 描述（Offer 或 Answer）
    @Published private(set) var localSDP: String?

    /// 连接延迟（毫秒）
    @Published private(set) var currentLatency: Int = 0

    /// 当前视频分辨率
    @Published private(set) var videoResolution: CGSize = .zero

    /// 当前帧率
    @Published private(set) var currentFPS: Int = 0

    /// ICE 候选收集完成
    @Published private(set) var iceGatheringComplete: Bool = false

    // MARK: - 私有属性

    /// WebRTC PeerConnectionFactory（全局单例）
    private let peerConnectionFactory: RTCPeerConnectionFactory

    /// 当前 PeerConnection
    private var peerConnection: RTCPeerConnection?

    /// 本地视频来源
    private var localVideoSource: RTCVideoSource?

    /// 本地视频轨道
    private var localVideoTrack: RTCVideoTrack?

    /// 本地音频来源
    private var localAudioSource: RTCAudioSource?

    /// 本地音频轨道
    private var localAudioTrack: RTCAudioTrack?

    /// ICE 服务器配置
    private let iceServers: [RTCIceServer]

    /// 当前会话 ID
    private var sessionId: String

    /// 消息回调发布者
    let onICECandidate = PassthroughSubject<SignalingMessage, Never>()

    /// 连接状态变化回调
    let onConnectionStateChanged = PassthroughSubject<WebRTCConnectionState, Never>()

    /// 帧率计算相关
    private var frameCount: Int = 0
    private var fpsTimer: Timer?
    private var lastFPSUpdate: Date = Date()

    // MARK: - 初始化

    /// 初始化 WebRTC 客户端
    /// - Parameters:
    ///   - iceServers: ICE 服务器列表
    ///   - sessionId: 会话标识
    init(iceServers: [String] = [], sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId

        // 初始化 WebRTC（全局只需一次）
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()

        // 配置 H.264 编码优先
        let encodingParams = RTCVideoEncoderSettings()
        encodingParams.name = RTCVideoCodecH264Name

        self.peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )

        // 配置 ICE 服务器
        self.iceServers = iceServers.map { url in
            RTCIceServer(url: url)
        }

        super.init()

        // 启动帧率监控
        startFPSMonitor()
    }

    deinit {
        stopFPSMonitor()
        close()
    }

    // MARK: - PeerConnection 管理

    /// 创建 PeerConnection
    /// - Returns: 是否创建成功
    @discardableResult
    func createPeerConnection() -> Bool {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.iceServers = iceServers

        // 限制视频带宽（2 Mbps）
        config.videoBitrate = 2_000_000

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )

        guard let connection = peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        ) else {
            print("[WebRTC] 创建 PeerConnection 失败")
            return false
        }

        self.peerConnection = connection
        print("[WebRTC] PeerConnection 创建成功")
        return true
    }

    /// 关闭连接并释放资源
    func close() {
        localVideoTrack = nil
        localAudioTrack = nil
        localVideoSource = nil
        localAudioSource = nil

        peerConnection?.close()
        peerConnection = nil

        connectionState = .closed
        onConnectionStateChanged.send(.closed)
        print("[WebRTC] 连接已关闭")
    }

    // MARK: - SDP 协商

    /// 创建 SDP Offer（异步版本，避免主线程死锁）
    /// - Parameter completion: 完成回调（Offer 字符串或 nil）
    func createOffer(completion: @escaping (String?) -> Void) {
        guard let peerConnection = peerConnection else {
            print("[WebRTC] PeerConnection 不存在，无法创建 Offer")
            completion(nil)
            return
        }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )

        peerConnection.offer(for: constraints) { sdp, error in
            if let error = error {
                print("[WebRTC] 创建 Offer 失败: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let sdp = sdp else {
                completion(nil)
                return
            }

            // 设置本地描述
            peerConnection.setLocalDescription(sdp) { setError in
                if let setError = setError {
                    print("[WebRTC] 设置本地 Offer 描述失败: \(setError.localizedDescription)")
                    completion(nil)
                } else {
                    print("[WebRTC] 本地 Offer 描述设置成功")
                    DispatchQueue.main.async {
                        self.localSDP = sdp.sdp
                    }
                    completion(sdp.sdp)
                }
            }
        }
    }

    /// 设置远端 SDP Answer
    /// - Parameter sdp: 远端 Answer 的 SDP 字符串
    func setRemoteAnswer(sdp: String) {
        guard let peerConnection = peerConnection else { return }

        let remoteSDP = RTCSessionDescription(type: .answer, sdp: sdp)
        peerConnection.setRemoteDescription(remoteSDP) { error in
            if let error = error {
                print("[WebRTC] 设置远端 Answer 失败: \(error.localizedDescription)")
            } else {
                print("[WebRTC] 远端 Answer 设置成功")
            }
        }
    }

    /// 设置远端 SDP Offer（接收端使用）
    /// - Parameter sdp: 远端 Offer 的 SDP 字符串
    func setRemoteOffer(sdp: String) {
        guard let peerConnection = peerConnection else { return }

        let remoteSDP = RTCSessionDescription(type: .offer, sdp: sdp)
        peerConnection.setRemoteDescription(remoteSDP) { [weak self] error in
            if let error = error {
                print("[WebRTC] 设置远端 Offer 失败: \(error.localizedDescription)")
            } else {
                print("[WebRTC] 远端 Offer 设置成功，开始创建 Answer")
                self?.createAnswer()
            }
        }
    }

    /// 创建 SDP Answer
    private func createAnswer() {
        guard let peerConnection = peerConnection else { return }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )

        peerConnection.answer(for: constraints) { [weak self] sdp, error in
            if let error = error {
                print("[WebRTC] 创建 Answer 失败: \(error.localizedDescription)")
                return
            }

            guard let sdp = sdp else { return }

            peerConnection.setLocalDescription(sdp) { setError in
                if let setError = setError {
                    print("[WebRTC] 设置本地 Answer 描述失败: \(setError.localizedDescription)")
                } else {
                    self?.localSDP = sdp.sdp
                    print("[WebRTC] 本地 Answer 描述设置成功")
                }
            }
        }
    }

    // MARK: - ICE 候选

    /// 添加远端 ICE 候选
    /// - Parameters:
    ///   - sdp: ICE 候选 SDP
    ///   - sdpMid: SDP 媒体标识
    ///   - sdpMLineIndex: SDP 媒体行索引
    func addICECandidate(sdp: String, sdpMid: String, sdpMLineIndex: Int32) {
        guard let peerConnection = peerConnection else { return }

        let candidate = RTCIceCandidate(
            sdp: sdp,
            sdpMid: sdpMid,
            sdpMLineIndex: sdpMLineIndex
        )
        peerConnection.add(candidate)
        print("[WebRTC] 添加远端 ICE 候选: \(sdp)")
    }

    // MARK: - 媒体轨道

    /// 创建本地视频轨道（用于 ReplayKit 视频流）
    /// - Returns: 本地视频轨道
    @discardableResult
    func createLocalVideoTrack() -> RTCVideoTrack? {
        // 创建视频来源（使用 capturer 模式，外部提供帧）
        localVideoSource = peerConnectionFactory.videoSource()

        guard let videoSource = localVideoSource else { return nil }

        // 创建视频轨道
        localVideoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
        guard let videoTrack = localVideoTrack else { return nil }

        // 添加到 PeerConnection
        peerConnection?.add(videoTrack)
        print("[WebRTC] 本地视频轨道已创建并添加")

        return videoTrack
    }

    /// 创建本地音频轨道
    /// - Returns: 本地音频轨道
    @discardableResult
    func createLocalAudioTrack() -> RTCAudioTrack? {
        localAudioSource = peerConnectionFactory.audioSource(with: nil)

        guard let audioSource = localAudioSource else { return nil }

        localAudioTrack = peerConnectionFactory.audioTrack(with: audioSource, trackId: "audio0")
        guard let audioTrack = localAudioTrack else { return nil }

        peerConnection?.add(audioTrack)
        print("[WebRTC] 本地音频轨道已创建并添加")

        return audioTrack
    }

    /// 推送视频帧（来自 ReplayKit）
    /// - Parameter pixelBuffer: 像素缓冲区
    func pushVideoFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let videoSource = localVideoSource else {
            print("[WebRTC] 视频来源不存在，无法推送帧")
            return
        }

        // 锁定像素缓冲区
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // 创建 RTCCVPixelBuffer（适配 GoogleWebRTC 的初始化方式）
        let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = Int64(timestamp.seconds * Double(NSEC_PER_SEC))

        videoSource.capturer(rtcBuffer, timeStampNs: timeStampNs)

        // 更新分辨率信息
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        if videoResolution.width != CGFloat(width) || videoResolution.height != CGFloat(height) {
            DispatchQueue.main.async {
                self.videoResolution = CGSize(width: width, height: height)
            }
        }

        // 帧计数
        frameCount += 1
    }

    /// 推送音频样本（来自 ReplayKit）
    /// - Parameter sampleBuffer: 音频样本缓冲区
    func pushAudioSample(sampleBuffer: CMSampleBuffer) {
        guard let audioSource = localAudioSource else { return }

        // 从 CMSampleBuffer 提取音频数据
        let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }

        let channels = Int(asbd.mChannelsPerFrame)
        let sampleRate = Int(asbd.mSampleRate)
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

        // 获取音频缓冲区数据
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListNeededSizeOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else { return }
        guard let data = audioBufferList.mBuffers.mData else { return }

        // 创建 RTC 音频帧
        let frame = RTCAudioFrame(
            buffer: data,
            numberOfFrames: Int(numSamples),
            channelCount: channels,
            sampleRate: sampleRate
        )

        audioSource.capturer(frame)
    }

    // MARK: - 帧率监控

    /// 启动帧率监控定时器
    private func startFPSMonitor() {
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastFPSUpdate)
            if elapsed > 0 {
                let fps = Int(Double(self.frameCount) / elapsed)
                DispatchQueue.main.async {
                    self.currentFPS = fps
                }
            }
            self.frameCount = 0
            self.lastFPSUpdate = now
        }
    }

    /// 停止帧率监控
    private func stopFPSMonitor() {
        fpsTimer?.invalidate()
        fpsTimer = nil
    }

    // MARK: - 统计信息

    /// 获取连接统计信息
    func getStats(completion: @escaping (RTCStatsReport) -> Void) {
        peerConnection?.statistics(completion: completion)
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClient: RTCPeerConnectionDelegate {

    /// 连接状态变化
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .new:
                self?.connectionState = .new
            case .connecting:
                self?.connectionState = .connecting
            case .connected:
                self?.connectionState = .connected
            case .disconnected:
                self?.connectionState = .disconnected
            case .failed:
                self?.connectionState = .failed
            case .closed:
                self?.connectionState = .closed
            @unknown default:
                self?.connectionState = .failed
            }
            print("[WebRTC] 连接状态变化: \(self?.connectionState.description ?? "未知")")
            if let newState = self?.connectionState {
                self?.onConnectionStateChanged.send(newState)
            }
        }
    }

    /// ICE 连接状态变化
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("[WebRTC] ICE 连接状态: \(newState.rawValue)")
    }

    /// ICE 候选收集变化
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        switch newState {
        case .new:
            print("[WebRTC] ICE 候选收集开始")
        case .gathering:
            print("[WebRTC] ICE 候选收集进行中...")
        case .complete:
            DispatchQueue.main.async { [weak self] in
                self?.iceGatheringComplete = true
            }
            print("[WebRTC] ICE 候选收集完成")
        @unknown default:
            break
        }
    }

    /// 生成 ICE 候选
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("[WebRTC] 生成 ICE 候选: \(candidate.sdp)")

        // 通过信令发送 ICE 候选
        let message = SignalingMessage.iceCandidate(
            sdp: candidate.sdp,
            sdpMid: candidate.sdpMid ?? "",
            sdpMLineIndex: candidate.sdpMLineIndex,
            sessionId: sessionId
        )
        onICECandidate.send(message)
    }

    /// 移除 ICE 候选
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("[WebRTC] 移除 ICE 候选")
    }

    /// 添加数据通道
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("[WebRTC] 数据通道已打开: \(dataChannel.label)")
    }

    /// 接收数据通道消息
    func peerConnection(_ peerConnection: RTCPeerConnection, didReceive message: RTCDataBuffer) {
        let data = message.data
        if let text = String(data: data, encoding: .utf8) {
            print("[WebRTC] 收到数据通道消息: \(text)")
        }
    }

    /// 数据通道状态变化
    func peerConnection(_ peerConnection: RTCPeerConnection, dataChannelDidChange state: RTCDataChannelState) {
        print("[WebRTC] 数据通道状态变化: \(state.rawValue)")
    }

    /// 添加远端媒体轨道
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd receiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        print("[WebRTC] 添加远端媒体轨道")
    }

    /// 移除远端媒体轨道
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove receiver: RTCRtpReceiver) {
        print("[WebRTC] 移除远端媒体轨道")
    }

    /// 添加远端流（已弃用，保留兼容）
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("[WebRTC] 添加远端流")
    }

    /// 移除远端流（已弃用，保留兼容）
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("[WebRTC] 移除远端流")
    }

    /// 重新协商
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("[WebRTC] 需要重新协商")
    }
}
