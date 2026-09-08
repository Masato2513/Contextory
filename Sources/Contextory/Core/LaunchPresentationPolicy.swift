import Foundation

/// 宿主启动来源与设置窗口展示策略。
///
/// FinderSync 通过显式参数请求后台启动；登录项由 AppDelegate 从系统 AppleEvent
/// 读取 `keyAELaunchedAsLogInItem`。普通启动不再依赖前台状态或延迟猜测。
public enum LaunchPresentationPolicy {
    public static let backgroundLaunchArgument = "--contextory-background"
    public static let permissionRefreshArgument = "--contextory-permission-refresh"
    public static let silentLaunchKey = "silent_launch_enabled"

    public static func isBackgroundRequest(
        arguments: [String],
        launchedAsLoginItem: Bool
    ) -> Bool {
        arguments.contains(backgroundLaunchArgument) || launchedAsLoginItem
    }

    public static func shouldShowSettingsWindowOnLaunch(
        silentLaunchEnabled: Bool,
        arguments: [String],
        launchedAsLoginItem: Bool
    ) -> Bool {
        if arguments.contains(backgroundLaunchArgument) {
            return false
        }
        return !launchedAsLoginItem || !silentLaunchEnabled
    }
}
