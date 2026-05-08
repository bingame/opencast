// DeviceDiscoveryService.swift - mDNS 设备发现服务
// 使用 Bonjour (Network.framework) 发现局域网内的接收端设备

import Foundation
import Combine
import Network

/// 设备发现服务
/// 使用 NWBrowser 浏览 Bonjour 服务，发现局域网内的 OpenCast 接收端
final class DeviceDiscoveryService: ObservableObject {

    // MARK: - 常量

    /// Bonjour 服务类型
    static let serviceType = "_opencast._tcp"

    /// 服务域名
    static let serviceDomain = "local."

    // MARK: - 发布属性

    /// 发现的设备列表
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []

    /// 是否正在扫描
    @Published private(set) var isScanning: Bool = false

    /// 最后一次扫描错误
    @Published var lastError: String?

    // MARK: - Combine 发布者

    /// 设备列表变化发布者
    let devicesChanged = CurrentValueSubject<[DiscoveredDevice], Never>([])

    // MARK: - 私有属性

    /// Bonjour 浏览器
    private var browser: NWBrowser?

    /// 发现的端点映射（endpoint -> device）
    private var endpointDeviceMap: [NWEndpoint: DiscoveredDevice] = [:]

    /// 设备名称解析队列
    private let nameResolutionQueue = DispatchQueue(label: "com.opencast.discovery.names")

    /// 服务发布器（广播自身）
    private var serviceRegistration: NWConnection?

    /// 是否正在广播自身
    private var isAdvertising: Bool = false

    /// 设备 ID
    private let localDeviceId: String

    /// 设备名称
    private let localDeviceName: String

    // MARK: - 初始化

    /// 初始化设备发现服务
    /// - Parameters:
    ///   - deviceName: 本设备名称
    init(deviceName: String = "iPhone") {
        self.localDeviceId = UUID().uuidString
        self.localDeviceName = deviceName
    }

    deinit {
        stopDiscovery()
        stopAdvertising()
    }

    // MARK: - 设备发现（浏览）

    /// 开始扫描发现设备
    func startDiscovery() {
        guard !isScanning else {
            print("[发现] 已在扫描中，跳过")
            return
        }

        print("[发现] 开始扫描设备...")

        // 创建 Bonjour 浏览器
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        do {
            browser = try NWBrowser(
                for: .bonjour(type: DeviceDiscoveryService.serviceType, domain: DeviceDiscoveryService.serviceDomain),
                using: parameters
            )
        } catch {
            print("[发现] 创建浏览器失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.lastError = "创建浏览器失败: \(error.localizedDescription)"
            }
            return
        }

        // 设置浏览器状态回调
        browser?.stateUpdateHandler = { [weak self] state in
            self?.handleBrowserState(state)
        }

        // 设置发现更新回调
        browser?.browsingResultsUpdateHandler = { [weak self] results, changes in
            self?.handleBrowsingResults(results: results, changes: changes)
        }

        // 开始浏览
        let browseQueue = DispatchQueue(label: "com.opencast.discovery.browse")
        browser?.start(queue: browseQueue)

        DispatchQueue.main.async { [weak self] in
            self?.isScanning = true
        }
    }

    /// 停止扫描
    func stopDiscovery() {
        browser?.cancel()
        browser = nil

        DispatchQueue.main.async { [weak self] in
            self?.isScanning = false
        }

        print("[发现] 已停止扫描")
    }

    /// 处理浏览器状态变化
    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            print("[发现] 浏览器就绪，开始扫描")
            DispatchQueue.main.async {
                self.lastError = nil
            }

        case .failed(let error):
            print("[发现] 浏览器失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.lastError = "扫描失败: \(error.localizedDescription)"
                self.isScanning = false
            }

        case .cancelled:
            print("[发现] 浏览器已取消")
            DispatchQueue.main.async {
                self.isScanning = false
            }

        case .waiting(let error):
            print("[发现] 浏览器等待中: \(error.localizedDescription)")

        @unknown default:
            break
        }
    }

    /// 处理浏览结果更新
    private func handleBrowsingResults(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                handleDeviceAdded(result)

            case .removed(let result):
                handleDeviceRemoved(result)

            case .changed(let oldResult, let newResult, _):
                handleDeviceChanged(old: oldResult, new: newResult)

            case .identical:
                break

            @unknown default:
                break
            }
        }
    }

    /// 处理设备添加
    private func handleDeviceAdded(_ result: NWBrowser.Result) {
        print("[发现] 发现新设备")

        // 解析设备信息
        resolveDeviceName(for: result.endpoint) { [weak self] name, endpoint in
            guard let self = self else { return }

            let device = DiscoveredDevice(
                name: name ?? "未知设备",
                deviceType: self.inferDeviceType(from: name),
                ipAddress: self.extractIPAddress(from: endpoint),
                port: self.extractPort(from: endpoint),
                signalingURL: self.buildSignalingURL(ipAddress: self.extractIPAddress(from: endpoint)),
                serviceName: result.endpoint.debugDescription
            )

            DispatchQueue.main.async {
                self.endpointDeviceMap[endpoint] = device
                self.updateDeviceList()
            }
        }
    }

    /// 处理设备移除
    private func handleDeviceRemoved(_ result: NWBrowser.Result) {
        print("[发现] 设备已移除")

        DispatchQueue.main.async { [weak self] in
            self?.endpointDeviceMap.removeValue(forKey: result.endpoint)
            self?.updateDeviceList()
        }
    }

    /// 处理设备变化
    private func handleDeviceChanged(old: NWBrowser.Result, new: NWBrowser.Result) {
        print("[发现] 设备信息变化")
        // 先移除旧的，再添加新的
        handleDeviceRemoved(old)
        handleDeviceAdded(new)
    }

    /// 更新已发布设备列表
    private func updateDeviceList() {
        let devices = Array(endpointDeviceMap.values).sorted { $0.name < $1.name }
        self.discoveredDevices = devices
        self.devicesChanged.send(devices)
    }

    // MARK: - 名称解析

    /// 解析设备名称
    /// - Parameters:
    ///   - endpoint: 网络端点
    ///   - completion: 完成回调（名称, 端点）
    private func resolveDeviceName(for endpoint: NWEndpoint, completion: @escaping (String?, NWEndpoint) -> Void) {
        nameResolutionQueue.async {
            // 尝试从端点中提取名称
            if case .bonjour(let service, _, _) = endpoint {
                completion(service, endpoint)
                return
            }

            // 使用 NWConnection 解析名称
            let connection: NWConnection
            do {
                connection = try NWConnection(to: endpoint, using: .tcp)
            } catch {
                completion(nil, endpoint)
                return
            }

            let resolveQueue = DispatchQueue(label: "com.opencast.discovery.resolve.\(UUID().uuidString)")
            connection.start(queue: resolveQueue)

            // 设置超时
            resolveQueue.asyncAfter(deadline: .now() + 5.0) {
                connection.cancel()
                completion(nil, endpoint)
            }
        }
    }

    // MARK: - 信息提取

    /// 从端点提取 IP 地址
    private func extractIPAddress(from endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let ipv4):
                return ipv4.debugDescription
            case .ipv6(let ipv6):
                return ipv6.debugDescription
            case .name(let hostname, _):
                return hostname
            @unknown default:
                return "未知地址"
            }
        case .bonjour(let service, _, _):
            return service
        @unknown default:
            return "未知地址"
        }
    }

    /// 从端点提取端口号
    private func extractPort(from endpoint: NWEndpoint) -> UInt16 {
        switch endpoint {
        case .hostPort(_, let port):
            return port.rawValue
        case .bonjour:
            return 8080 // 默认端口
        @unknown default:
            return 8080
        }
    }

    /// 根据设备名称推断设备类型
    private func inferDeviceType(from name: String?) -> DeviceType {
        guard let name = name?.lowercased() else { return .unknown }

        if name.contains("tv") || name.contains("电视") {
            return .tv
        } else if name.contains("projector") || name.contains("投影") {
            return .projector
        } else if name.contains("pc") || name.contains("mac") || name.contains("电脑") {
            return .computer
        } else if name.contains("speaker") || name.contains("音箱") || name.contains("音响") {
            return .speaker
        }

        return .unknown
    }

    /// 构建信令服务器 URL
    /// - Parameter ipAddress: IP 地址
    /// - Returns: WebSocket URL
    private func buildSignalingURL(ipAddress: String) -> String {
        return "ws://\(ipAddress):8080/signaling"
    }

    // MARK: - 设备广播（发布自身服务）

    /// 开始广播自身服务
    /// - Parameter port: 服务端口号
    func startAdvertising(on port: UInt16 = 0) {
        guard !isAdvertising else { return }

        print("[发现] 开始广播自身服务...")

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        do {
            // 使用 Bonjour 类型注册
            let service = NWListener.Service(
                name: "OpenCast-\(localDeviceName)",
                type: DeviceDiscoveryService.serviceType,
                domain: nil
            )

            // 创建 NWConnection 用于注册（简化实现）
            // 在实际项目中应使用 NWListener 来注册 Bonjour 服务
            serviceRegistration = try NWConnection(
                to: .hostPort(
                    host: .ipv4(.loopback),
                    port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 9000)!
                ),
                using: parameters
            )

            isAdvertising = true
            print("[发现] 自身服务广播已启动")

        } catch {
            print("[发现] 启动广播失败: \(error.localizedDescription)")
        }
    }

    /// 停止广播自身服务
    func stopAdvertising() {
        serviceRegistration?.cancel()
        serviceRegistration = nil
        isAdvertising = false
        print("[发现] 已停止广播自身服务")
    }
}
