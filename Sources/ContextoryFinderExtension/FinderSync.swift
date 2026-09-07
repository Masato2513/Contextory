import Cocoa
import FinderSync
import Darwin

// MARK: - FinderSync 主插件
@objc(FinderSync)
class FinderSync: FIFinderSync {
    private enum MenuIconAppearance: Equatable {
        case light
        case dark

        static var current: Self {
            UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
                ? .dark
                : .light
        }

        var appearance: NSAppearance {
            let name: NSAppearance.Name = self == .dark ? .darkAqua : .aqua
            return NSAppearance(named: name) ?? NSApp.effectiveAppearance
        }
    }

    private static let menuIconSize = NSSize(width: 16, height: 16)
    private static let menuIconConfiguration = NSImage.SymbolConfiguration(
        pointSize: 13,
        weight: .regular,
        scale: .medium
    ).applying(.preferringMonochrome())

    // MARK: - ActionTagMapper (双向唯一整数 Tag 映射表)
    // 使用稳定的整数 tag 传递菜单动作标识，避免依赖 representedObject。
    private struct MenuSelection: Equatable {
        let actionId: String
        let invocationKind: ActionInvocationKind
    }

    private static var tagToSelection: [Int: MenuSelection] = [:]
    private static var nextTag: Int = 1000
    private var currentObservedPathCount = 0
    private var menuIconAppearanceMode = MenuIconAppearance.current
    private lazy var menuIconAppearance = menuIconAppearanceMode.appearance
    private var menuIconCache: [String: NSImage] = [:]
    private lazy var heartbeatStore = ExtensionHeartbeatStore(
        fileURL: SharedStorageManager.shared.extensionHeartbeatURL
    )
    
    private static func getTag(
        for actionId: String,
        invocationKind: ActionInvocationKind
    ) -> Int {
        let selection = MenuSelection(actionId: actionId, invocationKind: invocationKind)
        if let existingTag = tagToSelection.first(where: { $0.value == selection })?.key {
            return existingTag
        }
        let assignedTag = nextTag
        tagToSelection[assignedTag] = selection
        nextTag += 1
        return assignedTag
    }
    
    private static func getSelection(for tag: Int) -> MenuSelection? {
        return tagToSelection[tag]
    }
    
    /// 当用户点击菜单项时的回调函数。
    @objc func actionMenuItemSelected(_ sender: NSMenuItem) {
        let tag = sender.tag
        logToSharedContainer("[FinderSync] [actionMenuItemSelected] 收到菜单点击事件，Tag: \(tag)", level: .debug)
        
        guard let selection = FinderSync.getSelection(for: tag) else {
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 错误: 无法根据 Tag \(tag) 映射出动作 ID")
            return
        }

        let actionId = selection.actionId
        // 实时获取当前选中的文件/目录路径，避免使用创建菜单时的静态路径数据。
        let controller = FIFinderSyncController.default()
        let targets: [URL]
        switch selection.invocationKind {
        case .items:
            targets = controller.selectedItemURLs() ?? []
        case .container:
            targets = controller.targetedURL().map { [$0] } ?? []
        }
        
        guard !targets.isEmpty else {
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 错误: 系统返回选中的物理路径为空")
            return
        }
        
        logToSharedContainer("[FinderSync] [actionMenuItemSelected] 解析动作成功: \(actionId), 目标路径总数: \(targets.count)", level: .debug)
        
        // 1. 写入中介共享动作队列文件
        let paths = targets.map { $0.path }

        do {
            let eventURL = try SharedStorageManager.shared.enqueueAction(
                actionId: actionId,
                paths: paths,
                invocationKind: selection.invocationKind
            )
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 成功向中介队列写入动作参数: \(eventURL.lastPathComponent)", level: .debug)
        } catch {
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 错误: 写入共享动作队列失败: \(error.localizedDescription)")
            return
        }
        
        // 2. 发送分布式空信号，通知宿主消费队列。
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("io.github.masato2513.Contextory.triggerActionSignal"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        
        logToSharedContainer("[FinderSync] [actionMenuItemSelected] 已发出动作触发信号", level: .debug)
        
        // 3. 仅在宿主 App 未运行时才拉起；已运行时 DistributedNotification 已足够唤醒消费队列。
        Self.ensureHostRunning()
    }
    
    override init() {
        super.init()
        
        logToSharedContainer("[FinderSync] 插件初始化启动...")
        
        // 1. 设置并应用我们需要监控的访达路径目录
        updateObservedDirectories()
        
        // 2. 监听来自主程序的目录范围配置变更。
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(configChanged),
            name: Notification.Name("io.github.masato2513.Contextory.configChanged"),
            object: nil
        )

        // 深浅色或高对比度等系统语义色发生变化时才失效图标缓存。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemColorsDidChange),
            name: NSColor.systemColorsDidChangeNotification,
            object: nil
        )

        // 3. 在插件进程中初始化固定的新建文件动作集。
        DefaultActionRegistry.registerAll()

        // 4. 主 App 是状态栏图标、输入弹窗与设置面板的唯一宿主。
        //    用户若曾强退主 App，菜单栏图标会消失；这里在 Extension 初始化时拉一次，
        //    让"重启 Finder / 重新进入受监控目录"就能把图标找回来，
        //    无需用户手动去 Launchpad 启动。
        Self.ensureHostRunning()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// 检查并按需拉起主 App（状态栏图标 + 设置面板宿主）。
    /// 已在跑则什么都不做，依赖 Launch Services 的进程级去重。
    static func ensureHostRunning() {
        let hostBundleID = "io.github.masato2513.Contextory"
        let isHostRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == hostBundleID
        }
        guard !isHostRunning else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: hostBundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.addsToRecentItems = false
        // activates 默认为 true 会抢焦点；主 App 是 .accessory，不会有窗口跳出，但还是显式关掉更稳。
        configuration.activates = false
        configuration.arguments = [LaunchPresentationPolicy.backgroundLaunchArgument]
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
    
    @objc private func configChanged() {
        logToSharedContainer("[FinderSync] 收到配置变更，刷新监听路径")
        updateObservedDirectories()
        
        // 强行刷新监控目录以立即生效。
        let currentURLs = FIFinderSyncController.default().directoryURLs
        FIFinderSyncController.default().directoryURLs = currentURLs
    }

    @objc private func systemColorsDidChange() {
        refreshMenuIconAppearance(force: true)
    }

    /// FinderSync 进程可能漏收系统颜色通知，因此每次菜单请求仅比较一次全局主题键。
    /// 未切换时只是一次 UserDefaults 读取和枚举比较，不会重建任何图标。
    private func refreshMenuIconAppearance(force: Bool = false) {
        let currentMode = MenuIconAppearance.current
        guard force || currentMode != menuIconAppearanceMode else { return }

        let didChangeMode = currentMode != menuIconAppearanceMode
        menuIconAppearanceMode = currentMode
        // 深浅色切换用全局主题键兜底；同一模式内的高对比度等变化仍采用 AppKit 外观。
        menuIconAppearance = didChangeMode ? currentMode.appearance : NSApp.effectiveAppearance
        menuIconCache.removeAll(keepingCapacity: true)
        logToSharedContainer("[FinderSync] 系统外观已变化，菜单图标缓存已失效", level: .debug)
    }
    
    /// 将日志写入统一 OSLog。调试日志默认不持久化，避免生产环境记录菜单渲染细节。
    private func logToSharedContainer(_ message: String, level: SharedLogLevel = .info) {
        switch level {
        case .info:  AppLog.info(message, category: .ext)
        case .debug: AppLog.debug(message, category: .ext)
        case .error: AppLog.error(message, category: .ext)
        }
    }
    
    /// 动态探测并应用需要监控的访达路径。
    private func updateObservedDirectories() {
        var observedURLs: Set<URL> = []
        
        // Finder 菜单范围与扩展的文件读取权限是两个边界。不能用 fileExists 过滤：
        // 受保护目录可能暂时不可读，但 Finder 仍可根据 directoryURLs 提供菜单。
        for folderURL in SharedStorageManager.shared.watchedDirectoryURLs {
            observedURLs.insert(folderURL.standardizedFileURL)
            logToSharedContainer("[FinderSync] 激活工作区监控: \(folderURL.path)", level: .debug)
        }
        
        FIFinderSyncController.default().directoryURLs = observedURLs
        currentObservedPathCount = observedURLs.count
        writeHeartbeat(force: true)
        logToSharedContainer("[FinderSync] 监控目录注册成功，当前激活数量: \(observedURLs.count)")
    }

    private func writeHeartbeat(force: Bool) {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        heartbeatStore.record(
            observedPathCount: currentObservedPathCount,
            version: version,
            processID: ProcessInfo.processInfo.processIdentifier,
            force: force
        )
    }
    
    // MARK: - 核心：动态渲染右键菜单
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer else {
            return nil
        }
        refreshMenuIconAppearance()
        writeHeartbeat(force: false)

        // 获取当前选中项目或当前所在空项目容器路径
        let targetURLs: [URL]
        if menuKind == .contextualMenuForItems {
            targetURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        } else if menuKind == .contextualMenuForContainer {
            if let containerURL = FIFinderSyncController.default().targetedURL() {
                targetURLs = [containerURL]
            } else {
                targetURLs = []
            }
        } else { return nil }
        
        guard !targetURLs.isEmpty else { return nil }
        
        logToSharedContainer("[FinderSync] 右键菜单触发渲染, 类型: \(menuKind == .contextualMenuForItems ? "Items" : "Container"), 目标路径: \(targetURLs.map { $0.path })", level: .debug)
        
        let invocationKind: ActionInvocationKind = menuKind == .contextualMenuForContainer
            ? .container
            : .items
        let isContainer = invocationKind == .container
        
        let menu = NSMenu(title: "右键助手")
        
        let dispatcher = ActionDispatcher.shared
        let parent = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "新建文件")
        for descriptor in DefaultActionRegistry.makeActions() {
            guard descriptor.isAvailable(for: targetURLs, isContainer: isContainer),
                  let action = dispatcher.action(forId: descriptor.actionId) else {
                continue
            }
            submenu.addItem(makeMenuItem(for: action, invocationKind: invocationKind))
        }
        if !submenu.items.isEmpty {
            parent.submenu = submenu
            menu.addItem(parent)
        }
        
        logToSharedContainer("[FinderSync] 菜单渲染完毕，主菜单 Items 数量: \(menu.items.count)", level: .debug)
        // 若全部为空则不展示任何项
        return menu.items.isEmpty ? nil : menu
    }

    private func makeMenuItem(
        for action: MenuAction,
        invocationKind: ActionInvocationKind
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.localizedTitle,
            action: #selector(actionMenuItemSelected(_:)),
            keyEquivalent: ""
        )
        item.tag = FinderSync.getTag(for: action.actionId, invocationKind: invocationKind)
        item.target = self

        if let iconName = action.iconName {
            item.image = makeMenuIcon(
                named: iconName,
                accessibilityDescription: action.localizedTitle
            )
        }

        return item
    }

    /// Finder 菜单不会替 Symbol 自动统一画布；在固定画布内等比居中，避免不同
    /// SF Symbol 的天然宽高让菜单图标忽大忽小。macOS 26 的 FinderSync 菜单不会
    /// 可靠地给扩展传入的模板图着色，因此外观变化后按当前语义前景色重建一次缓存。
    private func makeMenuIcon(
        named symbolName: String,
        accessibilityDescription: String
    ) -> NSImage? {
        if let cachedImage = menuIconCache[symbolName] {
            return cachedImage
        }

        var foregroundColor = NSColor.labelColor
        menuIconAppearance.performAsCurrentDrawingAppearance {
            foregroundColor = NSColor.labelColor.usingColorSpace(.deviceRGB)
                ?? NSColor.labelColor
        }
        let colorConfiguration = NSImage.SymbolConfiguration(
            hierarchicalColor: foregroundColor
        )
        let configuration = Self.menuIconConfiguration.applying(colorConfiguration)

        guard let source = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(configuration),
              source.size.width > 0,
              source.size.height > 0 else {
            return nil
        }

        let scale = min(
            Self.menuIconSize.width / source.size.width,
            Self.menuIconSize.height / source.size.height
        )
        let drawSize = NSSize(
            width: source.size.width * scale,
            height: source.size.height * scale
        )
        let drawRect = NSRect(
            x: (Self.menuIconSize.width - drawSize.width) / 2,
            y: (Self.menuIconSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        let image = NSImage(size: Self.menuIconSize, flipped: false) { _ in
            source.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            return true
        }
        // 保留已经解析好的前景色；设为模板图会再次触发 Finder 的错误黑色渲染。
        image.isTemplate = false
        menuIconCache[symbolName] = image
        return image
    }

}

// MARK: - 插件进程生命周期入口
@main
struct ExtensionMain {
    static func main() {
        _ = NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

@_silgen_name("NSExtensionMain")
@discardableResult
func NSExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
