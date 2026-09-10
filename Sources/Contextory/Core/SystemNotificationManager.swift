import AppKit
import Combine
import UserNotifications

/// 由系统负责通知的样式、展示和历史；宿主只保留最近一次失败，不创建悬浮窗口。
@MainActor
public final class SystemNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = SystemNotificationManager()

    public struct Failure: Identifiable {
        public let id = UUID()
        public let title: String
        public let detail: String
    }

    @Published public private(set) var latestFailure: Failure?
    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published public private(set) var authorizationSummary = "正在读取通知设置…"
    @Published public private(set) var isRequestingAuthorization = false

    public var onFailureChanged: (() -> Void)?
    public var onNotificationOpened: (() -> Void)?

    nonisolated private static let successIdentifier = "contextory.operation.success"
    nonisolated private static let failureIdentifier = "contextory.operation.failure"
    private var authorizationTask: Task<Void, Never>?
    private var generations: [String: Int] = [:]
    private lazy var center: UNUserNotificationCenter = {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    private override init() { super.init() }

    /// 启动时只注册回调，不在后台启动或登录时弹出权限请求。
    public func configure() {
        _ = center
    }

    nonisolated public static func show(title: String, content: String, isSuccess: Bool = true) {
        guard !isSuccess || successNotificationsEnabled else { return }
        Task { @MainActor in
            await shared.deliver(title: title, detail: content, isSuccess: isSuccess)
        }
    }

    nonisolated private static var successNotificationsEnabled: Bool {
        SharedStorageManager.shared.getBool(
            forKey: SharedStorageManager.Keys.enableSuccessNotifications,
            defaultValue: false
        )
    }

    public func refreshAuthorization() async {
        // 旧 SDK 的 UNNotificationSettings 不符合 Sendable；在系统回调内读取，
        // 仅将不可变值传回主线程，兼容 CI 的 Swift 6 严格并发检查。
        let settings: (authorization: Int, alertsEnabled: Bool, listEnabled: Bool) = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: (
                    settings.authorizationStatus.rawValue,
                    settings.alertSetting == .enabled,
                    settings.notificationCenterSetting == .enabled
                ))
            }
        }
        authorizationStatus = UNAuthorizationStatus(rawValue: settings.authorization) ?? .notDetermined
        switch authorizationStatus {
        case .notDetermined:
            authorizationSummary = "尚未授权；允许后可接收操作失败通知。"
        case .denied:
            authorizationSummary = "通知已关闭；操作失败仍可在菜单栏和此处查看。"
        case .authorized, .provisional, .ephemeral:
            if settings.alertsEnabled {
                authorizationSummary = "已允许系统通知，展示方式由系统通知设置决定。"
            } else if settings.listEnabled {
                authorizationSummary = "通知会保留在通知中心，横幅已关闭。"
            } else {
                authorizationSummary = "系统已关闭通知展示；操作失败仍可在菜单栏和此处查看。"
            }
        @unknown default:
            authorizationSummary = "请在系统设置中检查通知权限。"
        }
    }

    /// 首次失败或用户主动开启通知时请求授权；并发请求共用同一次系统提示。
    public func requestAuthorization() async {
        if let authorizationTask {
            await authorizationTask.value
            return
        }
        isRequestingAuthorization = true
        let task = Task { @MainActor in
            do {
                _ = try await center.requestAuthorization(options: [.alert])
                await refreshAuthorization()
            } catch {
                await refreshAuthorization()
                authorizationSummary = "无法请求通知权限，请在系统设置中检查。"
                SharedStorageManager.shared.writeLog("[通知] 请求授权失败：\(error.localizedDescription)", level: .error)
            }
        }
        authorizationTask = task
        await task.value
        authorizationTask = nil
        isRequestingAuthorization = false
    }

    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    public func clearFailure() {
        latestFailure = nil
        generations[Self.failureIdentifier, default: 0] += 1
        center.removePendingNotificationRequests(withIdentifiers: [Self.failureIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.failureIdentifier])
        onFailureChanged?()
    }

    public func clearSuccessNotifications() {
        generations[Self.successIdentifier, default: 0] += 1
        center.removePendingNotificationRequests(withIdentifiers: [Self.successIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.successIdentifier])
    }

    private func deliver(title: String, detail: String, isSuccess: Bool) async {
        if !isSuccess {
            latestFailure = Failure(title: title, detail: detail)
            SharedStorageManager.shared.writeLog("[操作失败] \(title)：\(detail)", level: .error)
            onFailureChanged?()
        }
        let identifier = isSuccess ? Self.successIdentifier : Self.failureIdentifier
        generations[identifier, default: 0] += 1
        let generation = generations[identifier]
        await refreshAuthorization()
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        guard generations[identifier] == generation,
              !isSuccess || Self.successNotificationsEnabled,
              authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = detail
        content.threadIdentifier = "contextory.operations"
        // 不请求声音或角标权限；同类通知只保留最新一条，避免频繁操作堆积记录。
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            authorizationSummary = "通知未能发送，请在系统设置中检查。"
            SharedStorageManager.shared.writeLog("[通知] 投递失败：\(error.localizedDescription)", level: .error)
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier == Self.successIdentifier && !Self.successNotificationsEnabled {
            completionHandler([])
        } else {
            // 设置窗口位于前台时也交给系统展示，仍遵守系统通知偏好与专注模式。
            completionHandler([.banner, .list])
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let request = response.notification.request
            let isFailure = request.identifier == Self.failureIdentifier
            let title = request.content.title
            let detail = request.content.body
            Task { @MainActor in
                let manager = Self.shared
                // 从通知冷启动时恢复其错误说明，已有更新的失败时保留当前状态。
                if isFailure && manager.latestFailure == nil {
                    manager.latestFailure = Failure(title: title, detail: detail)
                    manager.onFailureChanged?()
                }
                manager.onNotificationOpened?()
            }
        }
        completionHandler()
    }
}
