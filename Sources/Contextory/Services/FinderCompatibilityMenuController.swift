import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// 事件 tap 生命周期与 Finder 上下文解析设计参考并改编自 MacTweaks：
// https://github.com/NoahCLR/MacTweaks （MIT，完整声明见 THIRD_PARTY_NOTICES.md）。

extension Notification.Name {
    /// Finder 设置页变更兼容菜单开关后，通知宿主立即启停事件监听器。
    static let finderCompatibilityMenuConfigurationDidChange = Notification.Name(
        "io.github.masato2513.Contextory.finderCompatibilityMenuConfigurationDidChange"
    )
}

/// `⌘ + 右键`兼容菜单所需的辅助功能授权入口。
///
/// 这里只检查和引导授权，不轮询系统状态。控制器在用户切换前台 App 时进行一次
/// 事件驱动复查，授权后无需重启 Contextory。
enum FinderCompatibilityPermission {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func openAutomationSettings() {
        openPrivacyPane("Privacy_Automation")
    }

    private static func openPrivacyPane(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// FinderSync 在 File Provider 目录中被系统抑制时使用的独立兼容菜单。
///
/// 设计约束：
/// - 只在宿主进程中运行，不新增 helper 或常驻进程；
/// - 事件 tap 只订阅右键按下/抬起，不监听键盘或鼠标移动；
/// - 回调内只做 Finder、修饰键等常量级判断；Finder 路径解析在回调返回后执行；
/// - 普通右键完全透传，只有 Finder 中精确的 `⌘ + 右键`会被替换为自定义菜单。
final class FinderCompatibilityMenuController: NSObject, NSMenuDelegate {
    private struct MenuPresentationRequest {
        let finderLocation: CGPoint
        let popupLocation: NSPoint
    }

    private static let menuIconSize = NSSize(width: 16, height: 16)
    private static let menuIconConfiguration = NSImage.SymbolConfiguration(
        pointSize: 13,
        weight: .regular,
        scale: .medium
    ).applying(.preferringMonochrome())

    private var featureEnabled = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingMenuRequest: MenuPresentationRequest?
    /// popUp 是同步菜单跟踪调用；只允许一个调用栈存在，后续请求覆盖为最新位置。
    private var queuedMenuRequest: MenuPresentationRequest?
    private var isPresentingMenu = false
    private var activeMenu: NSMenu?
    /// 只跟踪 Finder 自己的菜单，避免其菜单尚未关闭时排队弹出兼容菜单。
    private var finderMenuObserver: AXObserver?
    private var observedFinderElement: AXUIElement?
    private var observedFinderPID: pid_t?
    private var finderMenuTrackingDepth = 0
    private var observesWorkspaceActivation = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationDidChange),
            name: .finderCompatibilityMenuConfigurationDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }

    /// 宿主完成动作注册后调用一次。默认关闭，只有用户主动开启才创建事件 tap。
    func start() {
        reloadConfiguration()
    }

    func stop() {
        featureEnabled = false
        stopEventTap()
        stopObservingFinderMenus()
        stopObservingWorkspaceActivation()
        queuedMenuRequest = nil
        isPresentingMenu = false
        activeMenu?.cancelTrackingWithoutAnimation()
        activeMenu = nil
    }

    @objc private func configurationDidChange() {
        reloadConfiguration()
    }

    private func reloadConfiguration() {
        featureEnabled = SharedStorageManager.shared.getBool(
            forKey: SharedStorageManager.Keys.finderCompatibilityMenuEnabled,
            defaultValue: false
        )
        reconcileRuntime()
    }

    private func reconcileRuntime() {
        guard featureEnabled else {
            stopEventTap()
            stopObservingFinderMenus()
            stopObservingWorkspaceActivation()
            return
        }

        startObservingWorkspaceActivation()

        guard FinderCompatibilityPermission.isAccessibilityTrusted else {
            stopEventTap()
            stopObservingFinderMenus()
            return
        }

        startObservingFinderMenusIfNeeded()

        if eventTap == nil {
            startEventTap()
        }
    }

    /// App 激活通知同时承担授权热刷新与 Finder 重启后的 AXObserver 重建。
    /// 仅在兼容菜单开启期间注册，不使用定时轮询。
    private func startObservingWorkspaceActivation() {
        guard !observesWorkspaceActivation else { return }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceApplicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        observesWorkspaceActivation = true
    }

    private func stopObservingWorkspaceActivation() {
        guard observesWorkspaceActivation else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        observesWorkspaceActivation = false
    }

    @objc private func workspaceApplicationDidActivate() {
        guard featureEnabled else { return }

        if !FinderCompatibilityPermission.isAccessibilityTrusted || eventTap == nil {
            reconcileRuntime()
            return
        }

        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
            startObservingFinderMenusIfNeeded()
        } else {
            // Finder 失去前台时其上下文菜单必然结束；此处也修正可能漏收的关闭通知。
            finderMenuTrackingDepth = 0
        }
    }

    private func startObservingFinderMenusIfNeeded() {
        guard let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first else {
            stopObservingFinderMenus()
            return
        }
        guard observedFinderPID != finder.processIdentifier else { return }

        stopObservingFinderMenus()

        let finderElement = AXUIElementCreateApplication(finder.processIdentifier)
        var observer: AXObserver?
        let createResult = AXObserverCreate(
            finder.processIdentifier,
            finderMenuObserverCallback,
            &observer
        )
        guard createResult == .success, let observer else {
            AppLog.error("无法创建 Finder 菜单状态观察器：\(createResult.rawValue)", category: .host)
            return
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let openedResult = AXObserverAddNotification(
            observer,
            finderElement,
            kAXMenuOpenedNotification as CFString,
            userInfo
        )
        let closedResult = AXObserverAddNotification(
            observer,
            finderElement,
            kAXMenuClosedNotification as CFString,
            userInfo
        )
        guard openedResult == .success, closedResult == .success else {
            if openedResult == .success {
                AXObserverRemoveNotification(
                    observer,
                    finderElement,
                    kAXMenuOpenedNotification as CFString
                )
            }
            if closedResult == .success {
                AXObserverRemoveNotification(
                    observer,
                    finderElement,
                    kAXMenuClosedNotification as CFString
                )
            }
            AppLog.error(
                "无法监听 Finder 菜单状态：open=\(openedResult.rawValue), close=\(closedResult.rawValue)",
                category: .host
            )
            return
        }

        finderMenuObserver = observer
        observedFinderElement = finderElement
        observedFinderPID = finder.processIdentifier
        finderMenuTrackingDepth = 0
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func stopObservingFinderMenus() {
        finderMenuTrackingDepth = 0
        observedFinderPID = nil

        guard let observer = finderMenuObserver else {
            observedFinderElement = nil
            return
        }

        if let finderElement = observedFinderElement {
            AXObserverRemoveNotification(
                observer,
                finderElement,
                kAXMenuOpenedNotification as CFString
            )
            AXObserverRemoveNotification(
                observer,
                finderElement,
                kAXMenuClosedNotification as CFString
            )
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        finderMenuObserver = nil
        observedFinderElement = nil
    }

    fileprivate func receiveFinderMenuNotification(_ notification: String) {
        switch notification {
        case kAXMenuOpenedNotification:
            finderMenuTrackingDepth += 1
        case kAXMenuClosedNotification:
            finderMenuTrackingDepth = max(0, finderMenuTrackingDepth - 1)
        default:
            break
        }
    }

    private func startEventTap() {
        let mask = (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: finderCompatibilityEventTapCallback,
            userInfo: userInfo
        ) else {
            AppLog.error("无法创建 Finder 兼容菜单事件监听器", category: .host)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        AppLog.info("Finder ⌘+右键兼容菜单已启用", category: .host)
    }

    private func stopEventTap() {
        pendingMenuRequest = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if FinderCompatibilityPermission.isAccessibilityTrusted, let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.stopEventTap()
                    self?.stopObservingFinderMenus()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .rightMouseDown {
            guard shouldCapture(event) else {
                // 普通右键或 Finder 系统菜单跟踪期间完全透传；同时清除尚未配对的
                // 兼容菜单按下状态，避免之后的 mouseUp 误触发延迟菜单。
                pendingMenuRequest = nil
                return Unmanaged.passUnretained(event)
            }
            pendingMenuRequest = MenuPresentationRequest(
                finderLocation: event.location,
                popupLocation: NSEvent.mouseLocation
            )

            // 菜单跟踪期间再次按住 Command 右键时，关闭旧菜单并吞掉本次按下；
            // 随后的 rightMouseUp 会在新位置重新解析 Finder 上下文并弹出菜单。
            // 不能把该事件透传给 Finder，否则会叠加打开系统右键菜单。
            activeMenu?.cancelTrackingWithoutAnimation()
            return nil
        }

        if type == .rightMouseUp, let request = pendingMenuRequest {
            pendingMenuRequest = nil
            DispatchQueue.main.async { [weak self] in
                self?.enqueueMenuPresentation(request)
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func shouldCapture(_ event: CGEvent) -> Bool {
        guard featureEnabled,
              finderMenuTrackingDepth == 0,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            return false
        }

        let flags = event.flags
        guard flags.contains(.maskCommand) else { return false }
        return flags.intersection([.maskAlternate, .maskControl, .maskShift]).isEmpty
    }

    /// 合并尚未显示的请求，只保留最新鼠标位置；若当前 popUp 仍在跟踪，等其返回
    /// 后再启动下一轮，禁止形成嵌套菜单调用栈。
    private func enqueueMenuPresentation(_ request: MenuPresentationRequest) {
        queuedMenuRequest = request
        presentQueuedMenuIfPossible()
    }

    private func presentQueuedMenuIfPossible() {
        guard !isPresentingMenu else { return }
        guard finderMenuTrackingDepth == 0 else {
            queuedMenuRequest = nil
            return
        }
        guard let request = queuedMenuRequest else { return }
        queuedMenuRequest = nil

        guard featureEnabled,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              let targetURL = FinderCompatibilityContext.targetURL(at: request.finderLocation) else {
            if featureEnabled,
               NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
                AppLog.error("⌘+右键未能解析当前 Finder 目录", category: .host)
                NSSound.beep()
            }
            return
        }

        let menu = buildMenu(targetURL: targetURL)
        guard !menu.items.isEmpty else { return }

        isPresentingMenu = true
        activeMenu = menu
        menu.delegate = self

        // 不激活宿主 App：保持 Finder 为前台，确保用户持续按住 Command 时，
        // 后续右键仍能被 shouldCapture 识别为 Finder 上下文。
        _ = menu.popUp(positioning: nil, at: request.popupLocation, in: nil)

        // popUp 是同步跟踪调用；返回后才能安全开始下一轮，避免重入。
        if activeMenu === menu {
            activeMenu = nil
        }
        isPresentingMenu = false

        if queuedMenuRequest != nil {
            DispatchQueue.main.async { [weak self] in
                self?.presentQueuedMenuIfPossible()
            }
        }
    }

    private func buildMenu(targetURL: URL) -> NSMenu {
        let menu = NSMenu(title: "右键助手")
        menu.autoenablesItems = false

        let parent = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        parent.image = menuIcon(
            named: "doc.badge.plus",
            accessibilityDescription: "新建文件"
        )

        let submenu = NSMenu(title: "新建文件")
        submenu.autoenablesItems = false

        for action in FileActionDescriptor.newFileActions {
            submenu.addItem(makeMenuItem(for: action, targetURL: targetURL))
        }

        guard !submenu.items.isEmpty else { return menu }
        parent.submenu = submenu
        menu.addItem(parent)
        menu.addItem(makeMenuItem(for: .copyPath, targetURL: targetURL))

        return menu
    }

    /// 新建文件与拷贝路径共用点击目标、图标和派发逻辑。
    private func makeMenuItem(for action: FileActionDescriptor, targetURL: URL) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.localizedTitle,
            action: #selector(performCompatibilityAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = CompatibilityMenuPayload(actionId: action.actionId, targetURL: targetURL)
        item.isEnabled = true
        item.image = menuIcon(named: action.iconName, accessibilityDescription: action.localizedTitle)
        return item
    }

    private func menuIcon(
        named symbolName: String?,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let symbolName,
              let baseImage = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: accessibilityDescription
              ),
              let image = baseImage.withSymbolConfiguration(Self.menuIconConfiguration) else {
            return nil
        }
        image.size = Self.menuIconSize
        image.isTemplate = true
        return image
    }

    @objc private func performCompatibilityAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? CompatibilityMenuPayload else {
            NSSound.beep()
            return
        }

        let submission = ActionDispatcher.shared.submit(
            actionId: payload.actionId,
            targetURLs: [payload.targetURL],
            invocationKind: .container
        ) { status in
            if status == .failed {
                AppLog.error("⌘+右键兼容菜单动作执行失败：\(payload.actionId)", category: .action)
            }
        }

        if submission == .rejected {
            NSSound.beep()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if activeMenu === menu {
            activeMenu = nil
        }
    }
}

private final class CompatibilityMenuPayload: NSObject {
    let actionId: String
    let targetURL: URL

    init(actionId: String, targetURL: URL) {
        self.actionId = actionId
        self.targetURL = targetURL
    }
}

/// 只负责把一次 Finder 点击解析为文件系统 URL，不保留任何目录或选中项缓存。
private enum FinderCompatibilityContext {
    static func targetURL(at mouseLocation: CGPoint) -> URL? {
        if let clickedItemURL = finderItemURL(at: mouseLocation) {
            return clickedItemURL
        }
        return currentFinderDirectoryURL()
    }

    /// 通过辅助功能命中测试取得鼠标下的 Finder 文件。兼容 Core Graphics 与
    /// AppKit 在不同系统版本上可能暴露的两种屏幕坐标方向。
    private static func finderItemURL(at mouseLocation: CGPoint) -> URL? {
        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else {
            return nil
        }

        let finderElement = AXUIElementCreateApplication(finder.processIdentifier)
        let points = uniquePoints([mouseLocation, NSEvent.mouseLocation])

        for point in points {
            var hitElement: AXUIElement?
            guard AXUIElementCopyElementAtPosition(
                finderElement,
                Float(point.x),
                Float(point.y),
                &hitElement
            ) == .success, let hitElement else {
                continue
            }

            if let url = fileURL(from: hitElement) {
                return url
            }
        }
        return nil
    }

    private static func fileURL(from element: AXUIElement) -> URL? {
        var current: AXUIElement? = element
        var depth = 0

        while let candidate = current, depth < 8 {
            // Finder 的应用级 AX 元素可能暴露自身 bundle URL；到达该层立即停止，
            // 防止在桌面空白区域误把 Finder.app 当作新建文件目标。
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                candidate,
                kAXRoleAttribute as CFString,
                &roleValue
            ) == .success,
               let role = roleValue as? String,
               role == (kAXApplicationRole as String) {
                break
            }

            for attribute in ["AXURL", "AXFilename", "AXPath", "AXDocument"] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    candidate,
                    attribute as CFString,
                    &value
                ) == .success,
                   let value,
                   let url = fileURL(fromAccessibilityValue: value),
                   isUsableFileURL(url) {
                    return url
                }
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                candidate,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                break
            }
            current = (parentValue as! AXUIElement)
            depth += 1
        }
        return nil
    }

    private static func fileURL(fromAccessibilityValue value: CFTypeRef) -> URL? {
        if let url = value as? URL, url.isFileURL {
            return url.standardizedFileURL
        }

        guard let string = value as? String, !string.isEmpty else { return nil }
        if let url = URL(string: string), url.isFileURL {
            return url.standardizedFileURL
        }
        guard string.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: string).standardizedFileURL
    }

    private static func isUsableFileURL(_ url: URL) -> Bool {
        let path = url.path
        guard !path.isEmpty,
              path != "/",
              path != "/Volumes" else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }

    /// 空白区域没有可命中的 AX 文件元素，通过 Finder Automation 取得插入位置；
    /// 没有 Finder 窗口时回退到桌面，因此也覆盖 iCloud 同步桌面。
    private static func currentFinderDirectoryURL() -> URL? {
        let script = """
        tell application "Finder"
            set folderPath to ""
            try
                try
                    set folderPath to URL of insertion location as text
                on error
                    set folderPath to POSIX path of ((insertion location) as alias)
                end try
            on error
                try
                    if (count of Finder windows) > 0 then
                        try
                            set folderPath to URL of (target of front Finder window) as text
                        on error
                            set folderPath to POSIX path of ((target of front Finder window) as alias)
                        end try
                    else
                        try
                            set folderPath to URL of desktop as text
                        on error
                            set folderPath to POSIX path of (desktop as alias)
                        end try
                    end if
                on error
                    try
                        set folderPath to URL of desktop as text
                    on error
                        set folderPath to POSIX path of (desktop as alias)
                    end try
                end try
            end try
            return folderPath
        end tell
        """

        var errorInfo: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        guard errorInfo == nil,
              let location = result?.stringValue,
              let url = fileURL(fromFinderLocation: location),
              isUsableFileURL(url) else {
            if let errorInfo {
                AppLog.error("读取 Finder 当前目录失败：\(errorInfo)", category: .host)
            }
            return nil
        }
        return url
    }

    private static func fileURL(fromFinderLocation location: String) -> URL? {
        if let url = URL(string: location), url.isFileURL {
            return url.standardizedFileURL
        }
        guard location.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: location).standardizedFileURL
    }

    private static func uniquePoints(_ points: [CGPoint]) -> [CGPoint] {
        var seen = Set<String>()
        return points.filter { point in
            seen.insert("\(point.x),\(point.y)").inserted
        }
    }
}

private let finderCompatibilityEventTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<FinderCompatibilityMenuController>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return controller.receive(type: type, event: event)
}

private let finderMenuObserverCallback: AXObserverCallback = {
    _, _, notification, userInfo in
    guard let userInfo else { return }
    let controller = Unmanaged<FinderCompatibilityMenuController>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    controller.receiveFinderMenuNotification(notification as String)
}
