// SignalingMessage.swift - 信令消息模型
// 定义 WebRTC 信令过程中使用的消息类型

import Foundation

/// 信令消息类型
/// 用于 WebRTC SDP 和 ICE 候选的交换
enum SignalingMessage: Codable {
    /// SDP Offer（发起连接）
    case offer(sdp: String, sessionId: String)

    /// SDP Answer（响应连接）
    case answer(sdp: String, sessionId: String)

    /// ICE 候选
    case iceCandidate(sdp: String, sdpMid: String, sdpMLineIndex: Int32, sessionId: String)

    /// 设备注册消息
    case register(deviceId: String, deviceName: String, deviceType: String)

    /// 设备注销消息
    case unregister(deviceId: String)

    /// 连接请求（从发送端到接收端）
    case connectRequest(fromDeviceId: String, toDeviceId: String)

    /// 连接响应
    case connectResponse(accepted: Bool, signalingURL: String?, sessionId: String)

    /// 断开连接
    case disconnect(sessionId: String)

    /// 心跳消息
    case heartbeat(deviceId: String)

    /// 错误消息
    case error(code: Int, message: String)

    // MARK: - 编解码

    /// 消息类型的键名
    private enum CodingKeys: String, CodingKey {
        case type
        case sdp
        case sessionId
        case sdpMid
        case sdpMLineIndex
        case deviceId
        case deviceName
        case deviceType
        case fromDeviceId
        case toDeviceId
        case accepted
        case signalingURL
        case code
        case message
    }

    /// 消息类型字符串
    private var typeValue: String {
        switch self {
        case .offer: return "offer"
        case .answer: return "answer"
        case .iceCandidate: return "iceCandidate"
        case .register: return "register"
        case .unregister: return "unregister"
        case .connectRequest: return "connectRequest"
        case .connectResponse: return "connectResponse"
        case .disconnect: return "disconnect"
        case .heartbeat: return "heartbeat"
        case .error: return "error"
        }
    }

    /// 编码为 JSON
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeValue, forKey: .type)

        switch self {
        case .offer(let sdp, let sessionId):
            try container.encode(sdp, forKey: .sdp)
            try container.encode(sessionId, forKey: .sessionId)

        case .answer(let sdp, let sessionId):
            try container.encode(sdp, forKey: .sdp)
            try container.encode(sessionId, forKey: .sessionId)

        case .iceCandidate(let sdp, let sdpMid, let sdpMLineIndex, let sessionId):
            try container.encode(sdp, forKey: .sdp)
            try container.encode(sdpMid, forKey: .sdpMid)
            try container.encode(sdpMLineIndex, forKey: .sdpMLineIndex)
            try container.encode(sessionId, forKey: .sessionId)

        case .register(let deviceId, let deviceName, let deviceType):
            try container.encode(deviceId, forKey: .deviceId)
            try container.encode(deviceName, forKey: .deviceName)
            try container.encode(deviceType, forKey: .deviceType)

        case .unregister(let deviceId):
            try container.encode(deviceId, forKey: .deviceId)

        case .connectRequest(let fromDeviceId, let toDeviceId):
            try container.encode(fromDeviceId, forKey: .fromDeviceId)
            try container.encode(toDeviceId, forKey: .toDeviceId)

        case .connectResponse(let accepted, let signalingURL, let sessionId):
            try container.encode(accepted, forKey: .accepted)
            try container.encodeIfPresent(signalingURL, forKey: .signalingURL)
            try container.encode(sessionId, forKey: .sessionId)

        case .disconnect(let sessionId):
            try container.encode(sessionId, forKey: .sessionId)

        case .heartbeat(let deviceId):
            try container.encode(deviceId, forKey: .deviceId)

        case .error(let code, let message):
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        }
    }

    /// 从 JSON 解码
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "offer":
            let sdp = try container.decode(String.self, forKey: .sdp)
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .offer(sdp: sdp, sessionId: sessionId)

        case "answer":
            let sdp = try container.decode(String.self, forKey: .sdp)
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .answer(sdp: sdp, sessionId: sessionId)

        case "iceCandidate":
            let sdp = try container.decode(String.self, forKey: .sdp)
            let sdpMid = try container.decode(String.self, forKey: .sdpMid)
            let sdpMLineIndex = try container.decode(Int32.self, forKey: .sdpMLineIndex)
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .iceCandidate(sdp: sdp, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, sessionId: sessionId)

        case "register":
            let deviceId = try container.decode(String.self, forKey: .deviceId)
            let deviceName = try container.decode(String.self, forKey: .deviceName)
            let deviceType = try container.decode(String.self, forKey: .deviceType)
            self = .register(deviceId: deviceId, deviceName: deviceName, deviceType: deviceType)

        case "unregister":
            let deviceId = try container.decode(String.self, forKey: .deviceId)
            self = .unregister(deviceId: deviceId)

        case "connectRequest":
            let fromDeviceId = try container.decode(String.self, forKey: .fromDeviceId)
            let toDeviceId = try container.decode(String.self, forKey: .toDeviceId)
            self = .connectRequest(fromDeviceId: fromDeviceId, toDeviceId: toDeviceId)

        case "connectResponse":
            let accepted = try container.decode(Bool.self, forKey: .accepted)
            let signalingURL = try container.decodeIfPresent(String.self, forKey: .signalingURL)
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .connectResponse(accepted: accepted, signalingURL: signalingURL, sessionId: sessionId)

        case "disconnect":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .disconnect(sessionId: sessionId)

        case "heartbeat":
            let deviceId = try container.decode(String.self, forKey: .deviceId)
            self = .heartbeat(deviceId: deviceId)

        case "error":
            let code = try container.decode(Int.self, forKey: .code)
            let message = try container.decode(String.self, forKey: .message)
            self = .error(code: code, message: message)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "未知的信令消息类型: \(type)"
            )
        }
    }
}

// MARK: - 便捷方法

extension SignalingMessage {
    /// 将消息转换为 JSON 数据
    func toJSON() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// 从 JSON 数据创建消息
    static func fromJSON(_ data: Data) -> SignalingMessage? {
        try? JSONDecoder().decode(SignalingMessage.self, from: data)
    }

    /// 将消息转换为 JSON 字符串
    func toJSONString() -> String? {
        guard let data = toJSON() else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
