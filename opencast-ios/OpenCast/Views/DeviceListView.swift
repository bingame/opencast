// DeviceListView.swift - 设备列表视图
// 显示发现的设备列表，支持搜索和设备选择

import SwiftUI

/// 设备列表视图
/// 展示通过 Bonjour 发现的所有接收端设备，支持搜索过滤和设备选择
struct DeviceListView: View {

    // MARK: - 属性

    /// 设备列表视图模型
    @ObservedObject var viewModel: DeviceListViewModel

    /// 投屏视图模型（用于设备选择后发起连接）
    @ObservedObject var castingViewModel: CastingViewModel

    // MARK: - 视图主体

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            searchBar

            // 设备列表
            if viewModel.filteredDevices.isEmpty {
                emptyStateView
            } else {
                deviceList
            }
        }
        .onAppear {
            // 设置设备选择回调
            viewModel.onDeviceSelected = { [weak castingViewModel] device in
                castingViewModel?.startCasting(to: device)
            }
        }
    }

    // MARK: - 搜索栏

    /// 搜索栏组件
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("搜索设备...", text: $viewModel.searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(.white)

            if !viewModel.searchText.isEmpty {
                Button(action: {
                    viewModel.searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - 设备列表

    /// 设备列表组件
    private var deviceList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 设备数量提示
                HStack {
                    Text("发现 \(viewModel.deviceCount) 个设备")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // 设备卡片列表
                ForEach(viewModel.filteredDevices) { device in
                    DeviceCardView(device: device)
                        .onTapGesture {
                            viewModel.selectDevice(device)
                        }
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - 空状态

    /// 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            // 空状态图标
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 120, height: 120)

                Image(systemName: viewModel.isScanning ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundColor(viewModel.isScanning ? .blue : .gray)
            }

            // 空状态文字
            VStack(spacing: 8) {
                Text(viewModel.isScanning ? "正在扫描设备..." : "未发现设备")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text(viewModel.isScanning
                     ? "请确保接收端设备与当前设备在同一局域网内"
                     : "请检查网络连接或手动刷新")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // 扫描指示器
            if viewModel.isScanning {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            }

            // 刷新按钮
            Button(action: {
                viewModel.refreshDevices()
            }) {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(20)
            }

            Spacer()
        }
    }
}

// MARK: - 设备卡片视图

/// 单个设备卡片视图
struct DeviceCardView: View {

    /// 设备信息
    let device: DiscoveredDevice

    /// 是否正在连接
    @State private var isConnecting = false

    var body: some View {
        HStack(spacing: 16) {
            // 设备图标
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: device.iconName)
                    .font(.title2)
                    .foregroundColor(.white)
            }

            // 设备信息
            VStack(alignment: .leading, spacing: 4) {
                // 设备名称
                Text(device.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                // 设备类型
                Text(device.deviceType.displayName)
                    .font(.caption)
                    .foregroundColor(.gray)

                // 设备地址
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.caption2)
                    Text(device.displayAddress)
                        .font(.caption)
                }
                .foregroundColor(.gray.opacity(0.8))
            }

            Spacer()

            // 连接按钮
            Button(action: {
                isConnecting = true
            }) {
                if isConnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        DeviceListView(
            viewModel: DeviceListViewModel(),
            castingViewModel: CastingViewModel()
        )
    }
}
