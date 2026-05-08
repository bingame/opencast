// SampleHandler.swift - Broadcast Upload Extension 实现
// 处理 ReplayKit 屏幕录制，将视频帧通过 App Group 共享给主 App

import ReplayKit
import CoreMedia
import Foundation

/// Broadcast Upload Extension 入口
/// 继承 RPBroadcastSampleHandler，处理系统屏幕录制的生命周期和视频帧
///
/// 功能说明：
/// 1. 接收 ReplayKit 采集的屏幕视频帧
/// 2. 将 CMSampleBuffer 转换为 CVPixelBuffer
/// 3. 通过 App Group 共享数据给主 App
/// 4. 处理广播开始/结束/错误事件
class SampleHandler: RPBroadcastSampleHandler {

    // MARK: - 属性

    /// App Group 共享容器
    private let appGroupIdentifier = "group.com.opencast.app"

    /// 共享 UserDefaults
    private var sharedDefaults: UserDefaults?

    /// 视频帧计数
    private var frameCount: Int = 0

    /// 开始时间
    private var startTime: Date?

    /// 是否已通知主 App 广播开始
    private var hasNotifiedStart: Bool = false

    /// 帧处理队列
    private let frameProcessingQueue = DispatchQueue(
        label: "com.opencast.broadcast.frameProcessing",
        qos: .userInteractive
    )

    // MARK: - 生命周期方法

    /// 广播启动
    /// - Parameters:
    ///   - broadcastConfiguration: 广播配置
    ///   - setupInfo: 设置信息
    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        print("[BroadcastExtension] 广播已启动")

        // 初始化共享 UserDefaults
        sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)

        // 记录开始时间
        startTime = Date()
        frameCount = 0

        // 标记广播状态
        sharedDefaults?.set(true, forKey: "isBroadcasting")

        // 通知主 App 广播已开始
        postNotification(name: "OpenCastBroadcastStarted")
        hasNotifiedStart = true

        // 清理旧的帧缓冲文件
        cleanupFrameBuffer()
    }

    /// 广播暂停
    override func broadcastPaused() {
        print("[BroadcastExtension] 广播已暂停")
    }

    /// 广播恢复
    override func broadcastResumed() {
        print("[BroadcastExtension] 广播已恢复")
    }

    /// 广播结束
    override func broadcastFinished() {
        print("[BroadcastExtension] 广播已结束，共处理 \(frameCount) 帧")

        // 标记广播状态
        sharedDefaults?.set(false, forKey: "isBroadcasting")

        // 通知主 App 广播已停止
        postNotification(name: "OpenCastBroadcastStopped")

        // 清理帧缓冲
        cleanupFrameBuffer()
    }

    /// 处理示例缓冲区（核心方法）
    /// - Parameters:
    ///   - sampleBuffer: 媒体样本缓冲区（包含视频或音频数据）
    ///   - sampleBufferType: 样本类型
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            processVideoSampleBuffer(sampleBuffer)

        case .audioApp:
            processAudioSampleBuffer(sampleBuffer)

        case .audioMic:
            // 麦克风音频暂不处理
            break

        @unknown default:
            print("[BroadcastExtension] 未知样本类型")
            break
        }
    }

    // MARK: - 视频处理

    /// 处理视频样本缓冲区
    /// - Parameter sampleBuffer: 视频样本缓冲区
    private func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        frameProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. 从 CMSampleBuffer 提取 CVPixelBuffer
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                print("[BroadcastExtension] 无法从 CMSampleBuffer 获取 CVPixelBuffer")
                return
            }

            // 2. 获取时间戳
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            // 3. 锁定像素缓冲区基地址
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

            defer {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            }

            // 4. 获取帧信息
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

            self.frameCount += 1

            // 每 60 帧打印一次日志
            if self.frameCount % 60 == 0 {
                let elapsed = Date().timeIntervalSince(self.startTime ?? Date())
                let fps = Double(self.frameCount) / elapsed
                print("[BroadcastExtension] 帧 #\(self.frameCount), "
                      + "分辨率: \(width)x\(height), "
                      + "格式: 0x\(String(format: "%X", format)), "
                      + "FPS: \(String(format: "%.1f", fps))")
            }

            // 5. 通过 App Group 共享帧数据给主 App
            self.shareFrameToMainApp(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    /// 将视频帧共享给主 App
    /// - Parameters:
    ///   - pixelBuffer: 像素缓冲区
    ///   - timestamp: 时间戳
    private func shareFrameToMainApp(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // 方案 1：通过 Darwin Notification 通知主 App（主 App 需要自行获取帧）
        // 这里使用通知方式，主 App 通过 CMSampleBuffer 回调获取帧数据

        // 方案 2：通过共享内存/文件传递帧数据
        // 对于低延迟场景，建议使用共享内存

        // 发送通知（包含帧元信息）
        let userInfo: [String: Any] = [
            "width": CVPixelBufferGetWidth(pixelBuffer),
            "height": CVPixelBufferGetHeight(pixelBuffer),
            "timestamp": timestamp.seconds,
            "frameIndex": frameCount
        ]

        DarwinNotificationCenter.postNotification(
            name: "OpenCastVideoFrame",
            userInfo: userInfo
        )

        // 方案 3：将帧写入共享文件（备选方案）
        // 注意：此方案有性能开销，仅在通知方式不满足需求时使用
        #if DEBUG
        if frameCount % 300 == 0 {
            writeFrameToFile(pixelBuffer: pixelBuffer, index: frameCount)
        }
        #endif
    }

    /// 将帧写入共享文件（调试用）
    /// - Parameters:
    ///   - pixelBuffer: 像素缓冲区
    ///   - index: 帧索引
    private func writeFrameToFile(pixelBuffer: CVPixelBuffer, index: Int) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return }

        let frameDir = containerURL.appendingPathComponent("FrameBuffer", isDirectory: true)
        try? FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)

        // 写入帧元信息（不写入实际像素数据以避免性能问题）
        let metaURL = frameDir.appendingPathComponent("frame_\(index).meta")
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let meta = "\(width),\(height),\(CVPixelBufferGetPixelFormatType(pixelBuffer))"
        try? meta.write(to: metaURL, atomically: true, encoding: .utf8)
    }

    // MARK: - 音频处理

    /// 处理音频样本缓冲区
    /// - Parameter sampleBuffer: 音频样本缓冲区
    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // 音频处理逻辑
        // 可在此处提取音频数据并通过 WebRTC 发送
        frameProcessingQueue.async {
            // 获取音频格式信息
            let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)

            if let asbd = asbd {
                let channels = asbd.mChannelsPerFrame
                let sampleRate = asbd.mSampleRate
                let samples = CMSampleBufferGetNumSamples(sampleBuffer)

                // 每 100 次打印一次日志
                if self.frameCount % 100 == 0 {
                    print("[BroadcastExtension] 音频帧 - "
                          + "声道: \(channels), "
                          + "采样率: \(sampleRate), "
                          + "样本数: \(samples)")
                }
            }

            // 音频数据通过 App Group 共享给主 App
            // 主 App 的 WebRTCClient 负责编码和发送
        }
    }

    // MARK: - 辅助方法

    /// 发送 Darwin 通知
    /// - Parameter name: 通知名称
    private func postNotification(name: String) {
        DarwinNotificationCenter.postNotification(name: name)
    }

    /// 清理帧缓冲文件
    private func cleanupFrameBuffer() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return }

        let frameDir = containerURL.appendingPathComponent("FrameBuffer", isDirectory: true)
        try? FileManager.default.removeItem(at: frameDir)
    }
}

// MARK: - Darwin 通知工具

/// Darwin 通知中心
/// 用于 Broadcast Extension 和主 App 之间的跨进程通信
enum DarwinNotificationCenter {

    /// 发送 Darwin 通知
    /// - Parameters:
    ///   - name: 通知名称
    ///   - userInfo: 附加信息（通过共享 UserDefaults 传递）
    static func postNotification(name: String, userInfo: [String: Any]? = nil) {
        // 将 userInfo 写入共享 UserDefaults
        if let userInfo = userInfo,
           let defaults = UserDefaults(suiteName: "group.com.opencast.app") {
            defaults.set(userInfo, forKey: "notification_\(name)")
        }

        // 发送 Darwin 通知
        let notificationName = CFNotificationName(name as CFString)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, notificationName, nil, nil, true)
    }
}
