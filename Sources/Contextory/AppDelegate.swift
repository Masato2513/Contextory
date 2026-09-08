import Cocoa
import SwiftUI
import CoreServices
import Darwin
import os.lock

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    
    fileprivate static var instance: AppDelegate?

    /// 设置窗口按需创建，关闭后完整释放 SwiftUI 视图树。
    /// 后台常驻时只保留状态栏与动作队列，避免为不可见界面长期持有 AttributeGraph。
    private var window: NSWindow?
    private var folderMonitor: SharedFolderMonitor?
    private var statusItem: NSStatusItem?
    /// 权限刷新会先启动新实例再结束旧实例，不能被当成用户主动退出。
    private var isTerminatingForRelaunch = false
    /// 系统登录项通过 kAEOpenApplication 携带的明确标记，不再用前台状态猜测启动来源。
    private var launchedAsLoginItem = false
    /// accessory → regular 切换后，统一在下一轮主线程显示窗口，避免重复打开竞态。
    private var pendingWindowPresentation: DispatchWorkItem?
    /// 窗口关闭与 Dock 身份切换都由 AppKit 动画驱动，延迟释放可避免在动画事务中销毁视图树。
    private var pendingWindowRelease: DispatchWorkItem?
    /// 替换旧的 objc_sync_enter(self)：
    /// - 旧实现把锁加在 NSObject self 上，和 AppKit 内部隐式锁高度耦合，
    ///   debug 时一旦死锁，spindump 几乎看不到哪一处先持有；
    /// - os_unfair_lock 是 Apple 推荐的纯互斥，不参与 runloop，
    ///   语义只覆盖"PendingActions 消费循环的 critical section"。
    private var pendingActionLock = os_unfair_lock()

    /// 专用串行队列：所有 processPendingAction 的真实工作都跑在这里。
    /// 必须用串行队列（不是 .global）：
    /// - 与 pendingActionLock 配合保证消费循环的 critical section 串行；
    /// - 同名右键动作短时间内突发 N 次时，按 FIFO 顺序消费，避免文件创建和 HUD
    ///   在并发 dispatch 路径上互相踩踏；
    /// - 不挂主线程：避免 applicationDidFinishLaunching 阶段第一笔 dispatch
    ///   触发 cfprefsd XPC 同步等待时把 main runloop 锁死（压测捕获的 P0 死锁）。
    private let pendingActionDispatchQueue = DispatchQueue(
        label: "io.github.masato2513.Contextory.pending-dispatch",
        qos: .userInitiated
    )
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return }
        launchedAsLoginItem = event.paramDescriptor(
            forKeyword: keyAELaunchedAsLogInItem
        )?.booleanValue == true
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard prepareRuntimeForLaunch() else {
            NSApp.terminate(nil)
            return
        }

        // 1. 初始化并注册固定的新建文件动作。
        registerDefaultActions()
        
        // 2. 监听来自 Extension 的纯信号通知（双保险机制一：分布式空信号通知，强制指定 suspensionBehavior: .deliverImmediately）
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExtensionActionSignal(_:)),
            name: Notification.Name("io.github.masato2513.Contextory.triggerActionSignal"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // P1-2：先把上次进程崩溃前未 ack 的 InFlight 孤儿事件搬回 PendingActions，
        // 再启动 folder-monitor。这样 reclaim 出来的事件会被本轮 processPendingAction 自然消费。
        SharedStorageManager.shared.reclaimAbandonedInFlightActions()
        
        // 3. 挂载 DispatchSource 动作队列监听服务。
        let pendingActionsURL = SharedStorageManager.shared.pendingActionsDirectoryURL
        let monitor = SharedFolderMonitor(folderURL: pendingActionsURL)
        monitor.onFolderChanged = { [weak self] in
            guard let self = self else { return }
            self.processPendingAction()
        }
        monitor.start()
        self.folderMonitor = monitor
        
        // 【关键修复】：启动后立刻检查并消费一次可能早已落盘的中介动作，彻底根治冷启动下拉起主程序却丢失首次点击事件的 Bug！
        self.processPendingAction()
        
        // 主程序默认保持轻量的菜单栏形态；设置窗口仅在需要显示时创建。
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        showSettingsWindowIfNeededForLaunch()
        handlePermissionRefreshLaunchIfNeeded()
        
        print("[App] 右键助手宿主程序启动并初始化完成 (双保险中介链路就绪)")
        
        // 【生产分发屏蔽】：仿真自检仅作为本地开发自检使用。为了避免用户在正常安装运行时，其 Downloads 目录下莫名凭空产生 txt 测试文件，生产包中默认关闭此仿真调用。
        // self.runLaunchSelfTest()
    }
    
    @objc private func handleExtensionActionSignal(_ notification: Notification) {
        print("[App] 收到 Extension 代理执行信号通知 (分布式信号渠道触发)")
        processPendingAction()
    }
    
    /// PendingActions 消费的对外入口。任何线程都可以调用，立即返回，
    /// 不会阻塞调用者（applicationDidFinishLaunching、kqueue 回调、分布式通知都是合法入口）。
    ///
    /// 设计原因（压测捕获的 P0 死锁复盘）：
    /// - 旧实现：在 applicationDidFinishLaunching 主线程上同步消费 PendingActions；
    ///   reclaim 把孤儿搬回 Pending 后，第一笔 dispatch 一旦走到 SharedHUDManager.show
    ///   → SharedStorageManager.getBool → cfprefsd XPC 同步等待，main runloop 还没起来，
    ///   cfprefsd 的回应没人接，进程永久 __ulock_wait 死锁；
    /// - 修复：消费循环全部下沉到 pendingActionDispatchQueue，主线程 0 阻塞。
    private func processPendingAction() {
        pendingActionDispatchQueue.async { [weak self] in
            self?.drainPendingActions()
        }
    }

    /// 真正的消费循环（pendingActionDispatchQueue 上跑）。
    /// 用 trylock 防止两条 async 任务同时进入；新到的回调若发现已有循环在跑直接返回，
    /// 因为 consumePendingActionLeases 内部自带原子 rename，下一次 FSEvents/通知会自然回来。
    private func drainPendingActions() {
        guard os_unfair_lock_trylock(&pendingActionLock) else { return }
        defer { os_unfair_lock_unlock(&pendingActionLock) }
        
        // P1-2：lease 形式拿事件——文件已搬到 InFlight/<pid>/，dispatcher 跑完才 ack 删除。
        // 中途崩溃/强退都会被下次启动的 reclaim 救回。
        let leases = SharedStorageManager.shared.consumePendingActionLeases()
        guard !leases.isEmpty else { return }

        SharedStorageManager.shared.writeLog("[App] [processPendingAction] 开始消费动作队列，事件数: \(leases.count)")

        for lease in leases {
            let event = lease.event
            SharedStorageManager.shared.writeLog("[App] [processPendingAction] 成功解析动作: \(event.actionId), 目标路径总数: \(event.paths.count), eventId: \(event.id)")

            let urls = event.paths.map { URL(fileURLWithPath: $0) }

            // 文件 I/O 在专用串行队列执行；需要交互的“其他…”动作会自行切回主线程。
            SharedStorageManager.shared.writeLog("[App] [processPendingAction] 即将由 ActionDispatcher 分发动作 \(event.actionId)...")
            let submission = ActionDispatcher.shared.submit(
                actionId: event.actionId,
                targetURLs: urls,
                invocationKind: event.invocationKind
            ) { status in
                SharedStorageManager.shared.writeLog(
                    "[App] [processPendingAction] 动作 \(event.actionId) 到达终态: \(String(describing: status))"
                )
                SharedStorageManager.shared.acknowledge(lease)
            }
            if submission == .rejected {
                SharedStorageManager.shared.writeLog(
                    "[App] [processPendingAction] 动作 \(event.actionId) 未被接管，已按失败终态确认",
                    level: .error
                )
            }
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        pendingWindowPresentation?.cancel()
        pendingWindowRelease?.cancel()
        folderMonitor?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !isTerminatingForRelaunch {
            let saved = SharedStorageManager.shared.setExplicitQuitRequested(true)
            if saved {
                SystemReloader.postConfigChanged()
                SharedStorageManager.shared.writeLog(
                    "[App] 用户主动退出，Finder 右键菜单已进入暂停状态"
                )
            } else {
                SharedStorageManager.shared.writeLog(
                    "[App] 无法保存主动退出状态，扩展可能继续自动恢复宿主",
                    level: .error
                )
            }
        }
        return .terminateNow
    }

    /// 后台恢复请求必须尊重用户主动退出；手动打开或登录启动则恢复完整功能。
    private func prepareRuntimeForLaunch() -> Bool {
        let isBackgroundRequest = LaunchPresentationPolicy.isBackgroundRequest(
            arguments: CommandLine.arguments,
            launchedAsLoginItem: launchedAsLoginItem
        )
        let storage = SharedStorageManager.shared

        if isBackgroundRequest {
            return !storage.isExplicitQuitRequested
        }

        guard storage.isExplicitQuitRequested else { return true }
        guard storage.setExplicitQuitRequested(false) else {
            storage.writeLog("[App] 无法清除主动退出状态", level: .error)
            return false
        }
        SystemReloader.postConfigChanged()
        storage.writeLog("[App] 检测到手动启动，Finder 右键菜单已恢复")
        return true
    }

    /// 设置页内部的权限刷新重启不改变用户启停意图。
    static func terminateForRelaunch() {
        instance?.isTerminatingForRelaunch = true
        NSApp.terminate(nil)
    }
    
    /// 注册默认的一套右键快捷操作
    private func registerDefaultActions() {
        let actions = DefaultActionRegistry.registerAll()
        print("[App] 已成功注册 \(actions.count) 个核心右键动作")
    }
    
    /// 【全自动仿真自检】在电脑上真实触发并调用验证整个跨沙盒多进程通信链路
    private func runLaunchSelfTest() {
        print("[App] [SelfTest] 自检将在 30 秒后全自动触发...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            print("[App] [SelfTest] 正在模拟 Extension 写入中介共享并触发右键点击信号...")
            
            // 仿真自检目标：在当前用户的 Downloads 文件夹下模拟新建一个文本文档
            let homeDir = NSHomeDirectory()
            let downloadsPath = (homeDir as NSString).appendingPathComponent("Downloads")
            
            print("[App] [SelfTest] 目标工作区: \(downloadsPath)")
            
            do {
                let eventURL = try SharedStorageManager.shared.enqueueAction(
                    actionId: "io.github.masato2513.Contextory.action.newfile.txt",
                    paths: [downloadsPath]
                )
                print("[App] [SelfTest] 1. 成功向中介共享写入队列动作参数: \(eventURL.path)")
            } catch {
                print("[App] [SelfTest] 错误: 写入队列动作失败: \(error.localizedDescription)")
                return
            }
            
            // 3. 通过 DistributedNotificationCenter 发送不带 userInfo 的纯分布式通知信号
            print("[App] [SelfTest] 2. 正在发送跨进程空信号 io.github.masato2513.Contextory.triggerActionSignal...")
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("io.github.masato2513.Contextory.triggerActionSignal"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            print("[App] [SelfTest] 3. 信号发送完毕，等待 AppDelegate 接收执行！")
        }
    }
    
    // MARK: - 系统菜单栏托盘管理
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        // 自定义资源是收紧透明边距后的 36×36 Retina 黑色蒙版；以 20 pt 模板图交给系统着色，
        // 自动适配浅色、深色、高对比度以及菜单按下状态。
        if let iconURL = Bundle.main.url(
            forResource: "StatusBarIcon",
            withExtension: "png"
        ), let image = NSImage(contentsOf: iconURL) {
            image.size = NSSize(width: 20, height: 20)
            image.isTemplate = true
            button.image = image
        }

        // 资源异常时先回退到所有支持版本均可用的系统图标。
        if button.image == nil,
           let fallback = NSImage(
               systemSymbolName: "line.3.horizontal",
               accessibilityDescription: "右键助手"
           ) {
            fallback.isTemplate = true
            button.image = fallback
        }

        // 最终兜底，避免极端情况下 statusItem 变成 0 宽不可见。
        if button.image == nil {
            button.title = "右"
        }
        
        let menu = NSMenu(title: "右键助手")
        menu.delegate = self
        rebuildStatusMenu(menu)
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let settingsItem = NSMenuItem(title: "打开设置…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "关于右键助手", action: #selector(showAboutDialog), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let silentLaunchItem = NSMenuItem(
            title: "静默启动",
            action: #selector(toggleSilentLaunch(_:)),
            keyEquivalent: ""
        )
        silentLaunchItem.target = self
        silentLaunchItem.state = isSilentLaunchEnabled ? .on : .off
        menu.addItem(silentLaunchItem)

        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(terminateApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private var isSilentLaunchEnabled: Bool {
        SharedStorageManager.shared.getBool(
            forKey: LaunchPresentationPolicy.silentLaunchKey,
            defaultValue: true
        )
    }

    private func showSettingsWindowIfNeededForLaunch() {
        guard LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            silentLaunchEnabled: isSilentLaunchEnabled,
            arguments: CommandLine.arguments,
            launchedAsLoginItem: launchedAsLoginItem
        ) else { return }
        showSettingsWindow()
    }

    private func handlePermissionRefreshLaunchIfNeeded() {
        guard CommandLine.arguments.contains(LaunchPresentationPolicy.permissionRefreshArgument) else {
            return
        }

        SystemReloader.postConfigChanged()
        SharedHUDManager.show(
            title: "正在刷新 Finder",
            content: "已重新打开右键助手，正在让 Finder 按新权限加载右键菜单",
            isSuccess: true
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let result = SystemReloader.restartFinder()
            DispatchQueue.main.async {
                guard !result.isSuccess else { return }
                SharedHUDManager.show(
                    title: "Finder 重启失败",
                    content: result.errorDescription ?? "请手动重启 Finder 或重新登录后再试",
                    isSuccess: false
                )
            }
        }
    }
    
    @objc private func showSettingsWindow() {
        pendingWindowPresentation?.cancel()
        pendingWindowPresentation = nil
        // 用户可能在关闭动画尚未结束时重新打开；此时继续复用原窗口，取消延迟回收。
        pendingWindowRelease?.cancel()
        pendingWindowRelease = nil

        // 设置页可见期间恢复标准 App 身份：展示 Dock 图标，并提供系统级退出入口。
        let settingsWindow = window ?? makeSettingsWindow()
        guard NSApp.setActivationPolicy(.regular) else {
            SharedStorageManager.shared.writeLog(
                "[App] 无法切换为标准窗口模式",
                level: .error
            )
            return
        }

        // 激活策略切换由 AppKit 提交到当前事件循环；下一轮再抢焦点，首次双击即可稳定显示。
        let presentation = DispatchWorkItem { [weak self, weak settingsWindow] in
            guard let self,
                  let settingsWindow,
                  self.window === settingsWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            self.pendingWindowPresentation = nil
        }
        pendingWindowPresentation = presentation
        DispatchQueue.main.async(execute: presentation)
    }

    /// SwiftUI 是设置页需要的重型界面层，不能在每次后台启动时预先实例化。
    /// 窗口关闭后会由 `windowWillClose` 清空，因此下次打开时重建最新状态。
    private func makeSettingsWindow() -> NSWindow {
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        settingsWindow.delegate = self
        // 由 AppDelegate 在关闭动画结束后统一释放，避免 AppKit 与 ARC 同时回收 NSWindow。
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.title = "右键助手"
        settingsWindow.center()
        settingsWindow.setFrameAutosaveName("MainWindow")
        settingsWindow.contentView = NSHostingView(rootView: ContentView())
        window = settingsWindow
        return settingsWindow
    }

    @objc private func toggleSilentLaunch(_ sender: NSMenuItem) {
        let newValue = !isSilentLaunchEnabled
        guard SharedStorageManager.shared.setBool(
            newValue,
            forKey: LaunchPresentationPolicy.silentLaunchKey
        ) else {
            sender.state = isSilentLaunchEnabled ? .on : .off
            SharedHUDManager.show(
                title: "设置保存失败",
                content: "无法写入静默启动设置，请检查共享目录权限后重试。",
                isSuccess: false
            )
            return
        }
        sender.state = newValue ? .on : .off
        SharedHUDManager.show(
            title: newValue ? "静默启动已启用" : "静默启动已关闭",
            content: newValue ? "后台拉起时仅保留菜单栏图标" : "下次启动会直接显示设置窗口",
            iconName: newValue ? "moon.fill" : "macwindow",
            isSuccess: true
        )
    }
    
    @objc private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "关于右键助手"
        
        // 从 Bundle 动态拉取当前最新的全局单源版本号
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        alert.informativeText = """
        右键助手 (Contextory)
        版本: v\(version)
        
        仅提供本地新建文件能力，不包含联网与更新检查。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        
        alert.window.level = .modalPanel
        alert.window.orderFrontRegardless()
        alert.runModal()
    }
    
    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }

        pendingWindowPresentation?.cancel()
        pendingWindowPresentation = nil
        pendingWindowRelease?.cancel()

        // windowWillClose 发生时 AppKit 的窗口/Dock 动画事务仍可能持有窗口图层。
        // 当前 runloop 只切回菜单栏身份，再给 AppKit 一个完整动画周期后释放 SwiftUI 视图树；
        // 否则在 _NSWindowTransformAnimation dealloc 阶段清空 contentView 可能触发野指针。
        let releaseWork = DispatchWorkItem { [weak self, weak closingWindow] in
            guard let self,
                  let closingWindow,
                  self.window === closingWindow,
                  !closingWindow.isVisible else { return }

            closingWindow.delegate = nil
            closingWindow.contentView = nil
            self.window = nil
            self.pendingWindowRelease = nil
            // SwiftUI 视图树已释放；仅在关闭设置页时请求 malloc 归还空闲页，不增加后台轮询。
            let reclaimedBytes = malloc_zone_pressure_relief(nil, 0)
            SharedStorageManager.shared.writeLog(
                "[App] 设置窗口已安全释放，已请求回收 \(reclaimedBytes) 字节，宿主继续以轻量菜单栏模式运行"
            )
        }
        pendingWindowRelease = releaseWork

        DispatchQueue.main.async { [weak self, weak closingWindow] in
            guard let self,
                  let closingWindow,
                  self.window === closingWindow,
                  !closingWindow.isVisible else { return }

            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: releaseWork)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }
}

// MARK: - 纯代码 AppKit 生命周期终极托管入口
@main
struct AppMain {
    static func main() {
        print("[AppMain] 纯代码自定义入口启动...")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.instance = delegate
        app.delegate = delegate
        print("[AppMain] 手动绑定 Delegate 成功，即将通过 app.run() 启动事件循环...")
        app.run()
    }
}
