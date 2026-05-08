// OpenCastApp.swift - App 入口
// OpenCast 投屏应用的入口点

import SwiftUI

/// OpenCast 应用入口
/// 配置应用的全局设置和初始视图
@main
struct OpenCastApp: App {

    // MARK: - 属性

    /// 投屏视图模型（全局共享）
    @StateObject private var castingViewModel = CastingViewModel()

    /// 设备发现服务（全局共享）
    @StateObject private var discoveryService = DeviceDiscoveryService()

    // MARK: - 场景配置

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(castingViewModel)
                .environmentObject(discoveryService)
                .onAppear {
                    // 应用启动时请求必要权限
                    requestPermissions()
                }
        }
    }

    // MARK: - 权限请求

    /// 请求应用运行所需的权限
    private func requestPermissions() {
        // 请求本地网络权限（iOS 14+）
        // 用于 Bonjour 设备发现
        requestLocalNetworkPermission()
    }

    /// 请求本地网络访问权限
    private func requestLocalNetworkPermission() {
        // 在 iOS 14+ 中，首次使用 Bonjour 时系统会自动弹出权限请求
        // 这里我们主动触发一次发现来触发权限弹窗
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            discoveryService.startDiscovery()
            // 短暂扫描后停止（实际扫描由 HomeView 控制）
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                discoveryService.stopDiscovery()
            }
        }
    }
}
