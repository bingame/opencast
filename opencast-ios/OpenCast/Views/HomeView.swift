// HomeView.swift - 主页视图
// 应用的主导航入口，包含设备列表和导航结构

import SwiftUI

/// 主页视图
/// 作为应用的根视图，提供导航到设备列表、投屏和设置页面的入口
struct HomeView: View {

    // MARK: - 状态属性

    /// 设备列表视图模型
    @StateObject private var deviceListVM: DeviceListViewModel

    /// 投屏视图模型（从环境获取，确保全局唯一实例）
    @EnvironmentObject var castingVM: CastingViewModel

    /// 设备发现服务（从环境获取，确保全局唯一实例）
    @EnvironmentObject var discoveryService: DeviceDiscoveryService

    /// 是否显示设置页面
    @State private var showSettings = false

    /// 是否正在投屏
    private var isCasting: Bool {
        castingVM.status.isCasting
    }

    // MARK: - 初始化

    init() {
        // 使用环境中的 discoveryService 初始化 DeviceListViewModel
        // 注意：这里使用一个临时的空实例，实际 discoveryService 在 onAppear 中注入
        _deviceListVM = StateObject(wrappedValue: DeviceListViewModel())
    }

    // MARK: - 视图主体

    var body: some View {
        NavigationView {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.1, green: 0.1, blue: 0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if isCasting {
                    // 投屏中显示投屏视图
                    CastingView(viewModel: castingVM)
                } else {
                    // 非投屏状态显示设备列表
                    DeviceListView(viewModel: deviceListVM, castingViewModel: castingVM)
                }
            }
            .navigationTitle(isCasting ? "投屏中" : "OpenCast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isCasting {
                        // 投屏中显示返回按钮
                        Button(action: {
                            castingVM.stopCasting()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // 设置按钮
                        Button(action: {
                            showSettings = true
                        }) {
                            Label("设置", systemImage: "gear")
                        }

                        // 关于按钮
                        Button(action: {
                            // 显示关于信息
                        }) {
                            Label("关于", systemImage: "info.circle")
                        }

                        if isCasting {
                            Divider()

                            // 暂停/恢复按钮
                            Button(action: {
                                if castingVM.status == .casting {
                                    castingVM.pauseCasting()
                                } else if castingVM.status == .paused {
                                    castingVM.resumeCasting()
                                }
                            }) {
                                Label(
                                    castingVM.status == .casting ? "暂停" : "恢复",
                                    systemImage: castingVM.status == .casting ? "pause.circle" : "play.circle"
                                )
                            }

                            // 停止投屏按钮
                            Button(role: .destructive, action: {
                                castingVM.stopCasting()
                            }) {
                                Label("停止投屏", systemImage: "stop.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("连接错误", isPresented: $castingVM.showError) {
                Button("确定", role: .cancel) {
                    castingVM.clearError()
                }
            } message: {
                Text(castingVM.errorMessage ?? "未知错误")
            }
            .alert("发现错误", isPresented: $deviceListVM.showError) {
                Button("确定", role: .cancel) {
                    deviceListVM.clearError()
                }
            } message: {
                Text(deviceListVM.errorMessage ?? "未知错误")
            }
            .alert("连接成功", isPresented: $castingVM.showConnectedAlert) {
                Button("开始投屏", action: {
                    castingVM.showBroadcastPicker()
                })
                Button("稍后", role: .cancel) {
                    castingVM.clearError()
                }
            } message: {
                if let device = castingVM.connectedDevice {
                    Text("已连接到 \(device.name)，是否开始投屏？")
                }
            }
            .onAppear {
                // 页面出现时开始扫描设备
                if !isCasting {
                    deviceListVM.startScanning()
                }
            }
            .onDisappear {
                // 页面消失时停止扫描
                if !isCasting {
                    deviceListVM.stopScanning()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 预览

#Preview {
    HomeView()
}
