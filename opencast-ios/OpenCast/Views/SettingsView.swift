// SettingsView.swift - 设置页面
/// 应用设置和配置页面

import SwiftUI
import UIKit

/// 设置视图
/// 提供应用配置选项，包括信令服务器地址、视频质量等设置
struct SettingsView: View {

    // MARK: - 状态属性

    /// 信令服务器地址
    @AppStorage("signalingServerURL") private var signalingServerURL = "ws://192.168.1.100:8080/signaling"

    /// 视频质量设置
    @AppStorage("videoQuality") private var videoQuality = VideoQuality.high.rawValue

    /// 最大视频分辨率
    @AppStorage("maxResolution") private var maxResolution = MaxResolution.resolution1080p.rawValue

    /// 是否自动发现设备
    @AppStorage("autoDiscovery") private var autoDiscovery = true

    /// 是否启用 H.264 硬件编码
    @AppStorage("hardwareEncoding") private var hardwareEncoding = true

    /// 是否显示连接统计
    @AppStorage("showStats") private var showStats = true

    /// 设备名称
    @AppStorage("deviceName") private var deviceName = UIDevice.current.name

    /// 显示模式
    @AppStorage("displayMode") private var displayMode = DisplayMode.system.rawValue

    /// 环境变量 - 关闭页面
    @Environment(\.dismiss) private var dismiss

    // MARK: - 视图主体

    var body: some View {
        NavigationView {
            Form {
                // MARK: - 连接设置
                connectionSection

                // MARK: - 视频设置
                videoSection

                // MARK: - 设备设置
                deviceSection

                // MARK: - 显示设置
                displaySection

                // MARK: - 关于
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }

    // MARK: - 连接设置

    /// 连接设置区域
    private var connectionSection: some View {
        Section {
            // 信令服务器地址
            VStack(alignment: .leading, spacing: 4) {
                Text("信令服务器地址")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("ws://192.168.1.100:8080/signaling", text: $signalingServerURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            .padding(.vertical, 4)

            // 自动发现设备
            Toggle("自动发现设备", isOn: $autoDiscovery)

        } header: {
            Text("连接")
        } footer: {
            Text("信令服务器用于 WebRTC 连接协商。确保服务器地址正确且可访问。")
        }
    }

    // MARK: - 视频设置

    /// 视频设置区域
    private var videoSection: some View {
        Section {
            // 视频质量
            Picker("视频质量", selection: $videoQuality) {
                ForEach(VideoQuality.allCases, id: \.rawValue) { quality in
                    Text(quality.displayName).tag(quality.rawValue)
                }
            }

            // 最大分辨率
            Picker("最大分辨率", selection: $maxResolution) {
                ForEach(MaxResolution.allCases, id: \.rawValue) { resolution in
                    Text(resolution.displayName).tag(resolution.rawValue)
                }
            }

            // 硬件编码
            Toggle("H.264 硬件编码", isOn: $hardwareEncoding)

        } header: {
            Text("视频")
        } footer: {
            Text("更高的视频质量需要更多的网络带宽。建议在 Wi-Fi 环境下使用高质量设置。")
        }
    }

    // MARK: - 设备设置

    /// 设备设置区域
    private var deviceSection: some View {
        Section {
            // 设备名称
            VStack(alignment: .leading, spacing: 4) {
                Text("设备名称")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("我的设备", text: $deviceName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.vertical, 4)

            // 显示统计信息
            Toggle("显示连接统计", isOn: $showStats)

        } header: {
            Text("设备")
        } footer: {
            Text("设备名称将显示在其他设备的发现列表中。")
        }
    }

    // MARK: - 显示设置

    /// 显示设置区域
    private var displaySection: some View {
        Section {
            Picker("显示模式", selection: $displayMode) {
                ForEach(DisplayMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
        } header: {
            Text("显示")
        }
    }

    // MARK: - 关于

    /// 关于信息区域
    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("构建")
                Spacer()
                Text("1")
                    .foregroundColor(.secondary)
            }

            Link(destination: URL(string: "https://github.com/opencast")!) {
                HStack {
                    Text("项目主页")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("关于")
        }
    }
}

// MARK: - 视频质量枚举

/// 视频质量选项
enum VideoQuality: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case ultra = "ultra"

    var displayName: String {
        switch self {
        case .low: return "低 (480p)"
        case .medium: return "中 (720p)"
        case .high: return "高 (1080p)"
        case .ultra: return "超高 (4K)"
        }
    }
}

// MARK: - 最大分辨率枚举

/// 最大分辨率选项
enum MaxResolution: String, CaseIterable {
    case resolution720p = "720p"
    case resolution1080p = "1080p"
    case resolution1440p = "1440p"
    case resolution4K = "4K"

    var displayName: String {
        switch self {
        case .resolution720p: return "720p (1280x720)"
        case .resolution1080p: return "1080p (1920x1080)"
        case .resolution1440p: return "1440p (2560x1440)"
        case .resolution4K: return "4K (3840x2160)"
        }
    }
}

// MARK: - 显示模式枚举

/// 显示模式选项
enum DisplayMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

// MARK: - 预览

#Preview {
    SettingsView()
}
