// ContentView.swift - 主视图
// 应用的根内容视图，提供导航和状态管理

import SwiftUI

/// 主内容视图
/// 作为应用的根视图，管理全局导航和状态
struct ContentView: View {

    // MARK: - 环境对象

    /// 投屏视图模型
    @EnvironmentObject var castingViewModel: CastingViewModel

    /// 设备发现服务
    @EnvironmentObject var discoveryService: DeviceDiscoveryService

    // MARK: - 视图主体

    var body: some View {
        HomeView()
            .environmentObject(castingViewModel)
            .environmentObject(discoveryService)
    }
}

// MARK: - 预览

#Preview {
    ContentView()
        .environmentObject(CastingViewModel())
        .environmentObject(DeviceDiscoveryService())
}
