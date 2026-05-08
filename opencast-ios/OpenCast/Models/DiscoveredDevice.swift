// DiscoveredDevice.swift - 发现的设备数据模型
// 定义通过 mDNS/Bonjour 发现的接收端设备信息

import Foundation
import Network

/// 发现的设备数据模型
/// 表示通过 Bonjour 服务发现到的接收端设备
struct DiscoveredDevice: Identifiable, Hashable, Codable {
    /// 设备唯一标识符
    let id: UUID

    /// 设备名称（如 "客厅电视"、"会议室大屏"）
    let name: String

    /// 设备类型
    let deviceType: DeviceType

    /// 设备 IP 地址
    let ipAddress: String

    /// 服务端口
    let port: UInt16

    /// 信令服务器 WebSocket 地址
    let signalingURL: String

    /// 设备是否可用
    var isAvailable: Bool

    /// 最后发现时间
    let lastSeen: Date

    /// 服务名称（Bonjour 服务标识）
    let serviceName: String

    /// 初始化方法
    /// - Parameters:
    ///   - id: 设备唯一标识，默认自动生成
    ///   - name: 设备显示名称
    ///   - deviceType: 设备类型
    ///   - ipAddress: 设备 IP 地址
    ///   - port: 服务端口号
    ///   - signalingURL: 信令服务器地址
    ///   - isAvailable: 是否可用
    ///   - serviceName: Bonjour 服务名称
    init(
        id: UUID = UUID(),
        name: String,
        deviceType: DeviceType = .unknown,
        ipAddress: String,
        port: UInt16 = 8080,
        signalingURL: String = "",
        isAvailable: Bool = true,
        serviceName: String = ""
    ) {
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.ipAddress = ipAddress
        self.port = port
        self.signalingURL = signalingURL
        self.isAvailable = isAvailable
        self.lastSeen = Date()
        self.serviceName = serviceName
    }

    /// 设备显示地址（IP:端口）
    var displayAddress: String {
        "\(ipAddress):\(port)"
    }

    /// 设备类型图标名称
    var iconName: String {
        switch deviceType {
        case .tv:
            return "tv"
        case .projector:
            return "projector"
        case .computer:
            return "desktopcomputer"
        case .speaker:
            return "speaker.wave.2"
        case .unknown:
            return "questionmark.circle"
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// 设备类型枚举
enum DeviceType: String, Codable, CaseIterable {
    /// 智能电视
    case tv = "tv"
    /// 投影仪
    case projector = "projector"
    /// 电脑
    case computer = "computer"
    /// 音箱
    case speaker = "speaker"
    /// 未知设备
    case unknown = "unknown"

    /// 设备类型的中文描述
    var displayName: String {
        switch self {
        case .tv:
            return "智能电视"
        case .projector:
            return "投影仪"
        case .computer:
            return "电脑"
        case .speaker:
            return "音箱"
        case .unknown:
            return "未知设备"
        }
    }
}
