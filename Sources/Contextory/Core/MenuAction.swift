import Foundation

public enum ActionCompletionStatus: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
}

public enum ActionSubmission: Equatable, Sendable {
    case accepted
    case rejected
}

/// 统一的右键动作抽象接口
public protocol MenuAction {
    /// 唯一标识符，用于分发调度
    var actionId: String { get }
    
    /// 显示在右键菜单中的国际化标题
    var localizedTitle: String { get }
    
    /// 图标名称（System Symbol 或本地资源）
    var iconName: String? { get }
    
    /// 执行前是否必须至少有一个仍存在的目标路径。
    var requiresExistingTargets: Bool { get }
    
    /// 判断此动作在当前选中的文件/文件夹下是否可用
    /// - Parameter urls: 用户右键选中的资源列表
    func isAvailable(for targetURLs: [URL]) -> Bool
    
    /// 判断此动作在自适应上下文（如右键空白背景）下是否可用
    /// - Parameters:
    ///   - targetURLs: 用户右键选中的资源列表
    ///   - isContainer: 是否为右键空白背景容器本身
    func isAvailable(for targetURLs: [URL], isContainer: Bool) -> Bool
    
    /// 执行动作
    /// - Parameter targetURLs: 用户右键选中的资源列表
    /// - Returns: 是否执行成功
    func execute(targetURLs: [URL]) -> Bool

    /// 提交动作并在真实终态回调。异步动作必须覆盖默认实现。
    func submit(
        targetURLs: [URL],
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission
}

// 提供默认实现
public extension MenuAction {
    func isAvailable(for targetURLs: [URL]) -> Bool {
        // 默认情况下，只要选中了对象，或者在空白处（此时 urls 为当前路径）就可用
        return true
    }
    
    func isAvailable(for targetURLs: [URL], isContainer: Bool) -> Bool {
        // 默认转发至老接口，保持向后兼容。
        return isAvailable(for: targetURLs)
    }
    
    var requiresExistingTargets: Bool {
        return true
    }

    func submit(
        targetURLs: [URL],
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission {
        completion(execute(targetURLs: targetURLs) ? .succeeded : .failed)
        return .accepted
    }
}
