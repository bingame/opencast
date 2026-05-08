// DarwinNotificationObserver.swift - Darwin 通知观察器
// 用于 Broadcast Extension 与主 App 之间的跨进程通信

import Foundation

/// Darwin 通知观察器
/// 封装 CFNotificationCenter 的 Darwin 通知监听，用于跨进程通信
///
/// 使用场景：
/// Broadcast Extension 运行在独立进程中，无法使用 NotificationCenter.default
/// 与主 App 通信。Darwin Notification 是 iOS 上唯一的跨进程通知机制。
///
/// 注意：Darwin Notification 不支持直接携带 userInfo，
/// 需要通过 App Group 的共享 UserDefaults 传递附加数据。
final class DarwinNotificationObserver {

    // MARK: - 属性

    /// 已注册的通知名称和回调
    private var observers: [String: (String) -> Void] = [:]

    /// CFNotificationCenter 中心引用
    private let center = CFNotificationCenterGetDarwinNotifyCenter()

    // MARK: - 初始化

    init() {}

    deinit {
        // 移除所有已注册的观察者
        for name in observers.keys {
            let cfName = CFNotificationName(name as CFString)
            CFNotificationCenterRemoveObserver(center, Unmanaged.passUnretained(self).toOpaque(), nil, cfName, .default)
        }
    }

    // MARK: - 公开方法

    /// 注册 Darwin 通知观察
    /// - Parameters:
    ///   - name: 通知名称
    ///   - callback: 收到通知时的回调
    func observe(name: String, callback: @escaping (String) -> Void) {
        observers[name] = callback

        let cfName = CFNotificationName(name as CFString)

        // 注册观察者
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { (observer, center, name, object, userInfo) in
                // 从 observer 指针获取 DarwinNotificationObserver 实例
                guard let observer = observer else { return }
                let observerObj = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()

                // 获取通知名称
                let notificationName = name?.rawValue as String? ?? ""

                // 在回调队列中执行
                DispatchQueue.main.async {
                    observerObj.handleNotification(name: notificationName)
                }
            },
            cfName,
            nil,
            .deliverImmediately
        )

        print("[Darwin通知] 已注册监听: \(name)")
    }

    /// 移除指定通知的观察
    /// - Parameter name: 通知名称
    func removeObserver(name: String) {
        observers.removeValue(forKey: name)
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterRemoveObserver(center, Unmanaged.passUnretained(self).toOpaque(), nil, cfName, .default)
    }

    // MARK: - 私有方法

    /// 处理收到的 Darwin 通知
    /// - Parameter name: 通知名称
    private func handleNotification(name: String) {
        guard let callback = observers[name] else { return }
        callback(name)
    }
}

// MARK: - 便捷发送方法

extension DarwinNotificationObserver {

    /// 发送 Darwin 通知
    /// - Parameters:
    ///   - name: 通知名称
    ///   - userInfo: 附加信息（通过共享 UserDefaults 传递）
    ///   - appGroupIdentifier: App Group 标识
    static func postNotification(
        name: String,
        userInfo: [String: Any]? = nil,
        appGroupIdentifier: String = "group.com.opencast.app"
    ) {
        // 将 userInfo 写入共享 UserDefaults（Darwin 通知不支持直接携带 userInfo）
        if let userInfo = userInfo,
           let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(userInfo, forKey: "notification_\(name)")
        }

        // 发送 Darwin 通知
        let cfName = CFNotificationName(name as CFString)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, cfName, nil, nil, true)
    }
}
