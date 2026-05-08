// SampleHandler.swift - ReplayKit Broadcast Extension 入口（主 App 内引用）
// 此文件为 Broadcast Extension 的接口定义，实际实现在 OpenCastBroadcastExtension 中

import Foundation
import ReplayKit

/// Broadcast Extension 共享接口
/// 定义主 App 与 Broadcast Extension 之间的通信协议
///
/// 注意：此文件仅作为主 App 中的接口引用。
/// Broadcast Extension 的实际实现位于 OpenCastBroadcastExtension/SampleHandler.swift
///
/// 主 App 与 Broadcast Extension 通过以下方式通信：
/// 1. App Group 共享 UserDefaults
/// 2. Darwin Notifications（跨进程通知）
/// 3. 共享文件（CMSampleBuffer 序列化）
///
/// App Group Identifier: group.com.opencast.app
enum BroadcastExtensionConstants {

    /// App Group 标识
    static let appGroupIdentifier = "group.com.opencast.app"

    /// Broadcast Extension Bundle ID
    static let extensionBundleId = "com.opencast.app.BroadcastExtension"

    // MARK: - 通知名称

    /// 广播开始通知
    static let broadcastStartedNotification = "OpenCastBroadcastStarted"

    /// 广播停止通知
    static let broadcastStoppedNotification = "OpenCastBroadcastStopped"

    /// 广播错误通知
    static let broadcastErrorNotification = "OpenCastBroadcastError"

    /// 视频帧可用通知
    static let videoFrameAvailableNotification = "OpenCastVideoFrame"

    // MARK: - UserDefaults Keys

    /// 是否正在广播
    static let isBroadcastingKey = "isBroadcasting"

    /// 视频配置信息
    static let videoConfigKey = "videoConfig"

    /// 错误信息
    static let errorInfoKey = "errorInfo"

    // MARK: - 共享文件

    /// 共享容器 URL
    static var sharedContainerURL: URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            fatalError("无法访问 App Group 共享容器。请确保 App Group 已正确配置。")
        }
        return containerURL
    }

    /// 视频帧缓冲目录
    static var frameBufferDirectory: URL {
        let url = sharedContainerURL.appendingPathComponent("FrameBuffer", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
