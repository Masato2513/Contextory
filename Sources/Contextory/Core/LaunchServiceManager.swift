import Foundation
import ServiceManagement

/// 现代 macOS 系统级自启动管理服务 (LaunchServiceManager)
/// 项目最低支持 macOS 15，直接使用现代 SMAppService API 注册或注销登录项。
public final class LaunchServiceManager {
    public nonisolated(unsafe) static let shared = LaunchServiceManager()

    private init() {}

    /// 获取当前自启动在系统中的真实注册状态
    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    /// 注册或注销开机自启动
    /// - Parameter enabled: true 为注册自启，false 为注销自启
    /// - Returns: 操作是否成功
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                    SharedStorageManager.shared.writeLog("[LaunchService] 成功向 macOS 注册 SMAppService 开机自启动")
                }
            } else if service.status == .enabled {
                try service.unregister()
                SharedStorageManager.shared.writeLog("[LaunchService] 成功向 macOS 注销 SMAppService 开机自启动")
            }
            return true
        } catch {
            SharedStorageManager.shared.writeLog("[LaunchService] 注册或注销自启动失败: \(error.localizedDescription)")
            return false
        }
    }
}
