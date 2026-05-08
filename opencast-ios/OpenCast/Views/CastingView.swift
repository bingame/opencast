// CastingView.swift - 投屏中视图
/// 投屏进行中的全屏显示视图，展示连接信息和控制按钮

import SwiftUI

/// 投屏视图
/// 投屏过程中的主界面，显示连接状态、视频信息和控制按钮
struct CastingView: View {

    // MARK: - 属性

    /// 投屏视图模型
    @ObservedObject var viewModel: CastingViewModel

    /// 投屏状态对应的颜色
    private var statusColor: Color {
        switch viewModel.status {
        case .casting:
            return .green
        case .connecting, .connected:
            return .blue
        case .paused:
            return .yellow
        case .error, .disconnecting:
            return .red
        default:
            return .gray
        }
    }

    /// 投屏状态对应的图标
    private var statusIcon: String {
        switch viewModel.status {
        case .casting:
            return "airplayvideo"
        case .connecting, .connected:
            return "arrow.triangle.2.circlepath"
        case .paused:
            return "pause.circle"
        case .error:
            return "exclamationmark.triangle"
        case .disconnecting:
            return "xmark.circle"
        default:
            return "questionmark.circle"
        }
    }

    // MARK: - 视图主体

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 投屏状态指示器
            VStack(spacing: 16) {
                // 状态图标动画
                ZStack {
                    // 外圈脉冲动画
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(viewModel.status == .casting ? 1.1 : 1.0)
                        .opacity(viewModel.status == .casting ? 0.5 : 0.0)
                        .animation(
                            viewModel.status == .casting
                            ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                            : .default,
                            value: viewModel.status
                        )

                    // 内圈
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 100, height: 100)

                    // 状态图标
                    Image(systemName: statusIcon)
                        .font(.system(size: 40))
                        .foregroundColor(statusColor)
                }

                // 状态文字
                Text(viewModel.status.description)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                // 目标设备名称
                if let device = viewModel.connectedDevice {
                    Text("正在投屏到 \(device.name)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 40)

            // 连接信息面板
            connectionInfoPanel
                .padding(.horizontal, 24)

            Spacer()

            // 底部控制按钮
            controlButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }

    // MARK: - 连接信息面板

    /// 连接信息面板组件
    private var connectionInfoPanel: some View {
        VStack(spacing: 16) {
            // 信息行
            HStack(spacing: 20) {
                // 投屏时长
                infoItem(
                    icon: "clock",
                    title: "时长",
                    value: viewModel.formattedDuration
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.1))

                // 视频分辨率
                infoItem(
                    icon: "video",
                    title: "分辨率",
                    value: viewModel.formattedResolution
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.1))

                // 延迟
                infoItem(
                    icon: "speedometer",
                    title: "延迟",
                    value: viewModel.formattedLatency
                )
            }

            // 帧率进度条
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("帧率")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(viewModel.fps) FPS")
                        .font(.caption)
                        .foregroundColor(.white)
                        .fontWeight(.medium)
                }

                // 帧率指示条
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // 背景
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))

                        // 帧率指示（60fps 为满）
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                fpsColor(for: viewModel.fps)
                            )
                            .frame(width: fpsBarWidth(in: geometry.size.width))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }

    /// 单个信息项视图
    /// - Parameters:
    ///   - icon: SF Symbol 图标名
    ///   - title: 标题
    ///   - value: 值
    private func infoItem(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    /// 帧率对应的颜色
    /// - Parameter fps: 帧率值
    /// - Returns: 颜色
    private func fpsColor(for fps: Int) -> Color {
        if fps >= 50 {
            return .green
        } else if fps >= 30 {
            return .yellow
        } else {
            return .red
        }
    }

    /// 帧率进度条宽度
    /// - Parameter totalWidth: 总宽度
    /// - Returns: 帧率条宽度
    private func fpsBarWidth(in totalWidth: CGFloat) -> CGFloat {
        let targetFPS: CGFloat = 60
        let ratio = min(CGFloat(viewModel.fps) / targetFPS, 1.0)
        return totalWidth * ratio
    }

    // MARK: - 控制按钮

    /// 底部控制按钮区域
    private var controlButtons: some View {
        HStack(spacing: 20) {
            // 暂停/恢复按钮
            Button(action: {
                if viewModel.status == .casting {
                    viewModel.pauseCasting()
                } else if viewModel.status == .paused {
                    viewModel.resumeCasting()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 60, height: 60)

                    Image(systemName: viewModel.status == .casting ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .disabled(viewModel.status != .casting && viewModel.status != .paused)

            // 停止投屏按钮
            Button(action: {
                viewModel.stopCasting()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            }
            .disabled(viewModel.status == .idle || viewModel.status == .disconnecting)
        }
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CastingView(viewModel: CastingViewModel())
    }
}
