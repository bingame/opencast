// swift-tools-version: 5.9
// Package.swift - OpenCast iOS 投屏项目依赖管理
//
// 注意：GoogleWebRTC 官方不直接提供 SPM 支持。
// 推荐通过 CocoaPods 或手动集成 GoogleWebRTC。
// 此 Package.swift 仅用于定义项目结构。
// 实际开发请使用 CocoaPods：
//   pod 'GoogleWebRTC', '~> 1.1.32000'

import PackageDescription

let package = Package(
    name: "OpenCast",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .executable(
            name: "OpenCast",
            targets: ["OpenCast"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "OpenCast",
            dependencies: [],
            path: "OpenCast",
            exclude: ["Broadcast"],
            sources: ["App", "Models", "Services", "Views", "ViewModels"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreAnimation"),
                .linkedFramework("ReplayKit"),
                .linkedFramework("Network"),
                .linkedFramework("WebKit"),
                .linkedFramework("UIKit"),
            ]
        )
    ]
)
