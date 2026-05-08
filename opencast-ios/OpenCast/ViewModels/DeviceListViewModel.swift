// DeviceListViewModel.swift - 设备列表视图模型
// 管理设备发现生命周期和设备选择逻辑

import Foundation
import Combine
import SwiftUI

/// 设备列表视图模型
/// 负责管理设备发现、设备列表状态和设备选择交互
@MainActor
final class DeviceListViewModel: ObservableObject {

    // MARK: - 发布属性

    /// 发现的设备列表
    @Published var devices: [DiscoveredDevice] = []

    /// 是否正在扫描
    @Published var isScanning: Bool = false

    /// 是否正在连接设备
    @Published var isConnecting: Bool = false

    /// 当前选中的设备
    @Published var selectedDevice: DiscoveredDevice?

    /// 错误信息
    @Published var errorMessage: String?

    /// 是否显示错误提示
    @Published var showError: Bool = false

    /// 搜索过滤关键字
    @Published var searchText: String = ""

    /// 过滤后的设备列表
    var filteredDevices: [DiscoveredDevice] {
        if searchText.isEmpty {
            return devices
        }
        return devices.filter { device in
            device.name.localizedCaseInsensitiveContains(searchText) ||
            device.ipAddress.localizedCaseInsensitiveContains(searchText) ||
            device.deviceType.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// 设备数量
    var deviceCount: Int {
        filteredDevices.count
    }

    // MARK: - 私有属性

    /// 设备发现服务
    private let discoveryService: DeviceDiscoveryService

    /// Combine 取消集合
    private var cancellables = Set<AnyCancellable>()

    /// 设备选择回调
    var onDeviceSelected: ((DiscoveredDevice) -> Void)?

    // MARK: - 初始化

    /// 初始化视图模型
    /// - Parameter discoveryService: 设备发现服务实例
    init(discoveryService: DeviceDiscoveryService = DeviceDiscoveryService()) {
        self.discoveryService = discoveryService

        // 绑定发现服务的设备列表
        discoveryService.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.devices = devices
            }
            .store(in: &cancellables)

        // 绑定扫描状态
        discoveryService.$isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isScanning in
                self?.isScanning = isScanning
            }
            .store(in: &cancellables)

        // 绑定错误信息
        discoveryService.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.errorMessage = error
                    self?.showError = true
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        discoveryService.stopDiscovery()
    }

    // MARK: - 扫描控制

    /// 开始扫描设备
    func startScanning() {
        print("[设备列表] 开始扫描设备")
        discoveryService.startDiscovery()
    }

    /// 停止扫描设备
    func stopScanning() {
        print("[设备列表] 停止扫描设备")
        discoveryService.stopDiscovery()
    }

    /// 切换扫描状态
    func toggleScanning() {
        if isScanning {
            stopScanning()
        } else {
            startScanning()
        }
    }

    /// 刷新设备列表
    func refreshDevices() {
        print("[设备列表] 刷新设备列表")
        stopScanning()
        // 短暂延迟后重新开始扫描
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startScanning()
        }
    }

    // MARK: - 设备选择

    /// 选择设备并准备连接
    /// - Parameter device: 选中的设备
    func selectDevice(_ device: DiscoveredDevice) {
        print("[设备列表] 选择设备: \(device.name) (\(device.displayAddress))")
        selectedDevice = device
        isConnecting = true

        // 通知外部进行连接
        onDeviceSelected?(device)
    }

    /// 取消设备选择
    func cancelSelection() {
        selectedDevice = nil
        isConnecting = false
    }

    // MARK: - 错误处理

    /// 清除错误信息
    func clearError() {
        errorMessage = nil
        showError = false
    }
}
