import AppKit

/// 两种菜单统一提交原始目标 URL，复制动作不把文件转换为父目录，也不读取云端内容。
public final class CopyPathAction: MenuAction, @unchecked Sendable {
    public let actionId = FileActionDescriptor.copyPath.actionId
    public let localizedTitle = FileActionDescriptor.copyPath.localizedTitle
    public let iconName: String? = FileActionDescriptor.copyPath.iconName
    public let requiresExistingTargets = false

    public init() {}

    public func isAvailable(for targetURLs: [URL]) -> Bool {
        !targetURLs.isEmpty && targetURLs.allSatisfy { $0.isFileURL && !$0.path.isEmpty }
    }

    public func execute(targetURLs: [URL]) -> Bool {
        guard isAvailable(for: targetURLs) else { return false }
        if Thread.isMainThread {
            return MainActor.assumeIsolated { copy(targetURLs) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { copy(targetURLs) }
        }
    }

    public func submit(
        targetURLs: [URL],
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission {
        guard isAvailable(for: targetURLs) else {
            completion(.failed)
            return .rejected
        }
        DispatchQueue.main.async { [self] in
            completion(copy(targetURLs) ? .succeeded : .failed)
        }
        return .accepted
    }

    @MainActor
    private func copy(_ targetURLs: [URL]) -> Bool {
        // 使用可直接粘贴的本机绝对路径，保留中文和空格；多选项目以换行分隔。
        let text = targetURLs.map(\.path).joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            SystemNotificationManager.show(
                title: "复制路径失败",
                content: "无法写入剪贴板，请重试。",
                isSuccess: false
            )
            return false
        }
        SystemNotificationManager.show(
            title: "路径已复制",
            content: targetURLs.count == 1 ? text : "已复制 \(targetURLs.count) 个项目的路径",
            isSuccess: true
        )
        return true
    }
}
