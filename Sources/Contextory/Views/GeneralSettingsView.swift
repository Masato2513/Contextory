import SwiftUI

struct OverviewSettingsView: View {
    @EnvironmentObject private var session: SettingsSession
    @ObservedObject private var notifications = SystemNotificationManager.shared
    @State private var isLaunchEnabled = false
    @State private var isSilentLaunchEnabled = true
    @State private var showsSuccessNotifications = false

    private var launchEnabledBinding: Binding<Bool> {
        Binding(
            get: { isLaunchEnabled },
            set: { newValue in
                let previousValue = isLaunchEnabled
                guard LaunchServiceManager.shared.setEnabled(newValue) else {
                    isLaunchEnabled = LaunchServiceManager.shared.isEnabled
                    SystemNotificationManager.show(
                        title: "自启设置失败",
                        content: "请前往系统设置检查登录项权限",
                        isSuccess: false
                    )
                    return
                }
                guard SharedStorageManager.shared.setBool(
                    newValue,
                    forKey: "shouldStartOnLaunch"
                ) else {
                    _ = LaunchServiceManager.shared.setEnabled(previousValue)
                    isLaunchEnabled = LaunchServiceManager.shared.isEnabled
                    showConfigurationSaveFailure("登录时启动")
                    return
                }
                isLaunchEnabled = newValue
            }
        )
    }

    var body: some View {
        SettingsForm {
            SettingsSection("服务状态") {
                ExtensionStatusBanner()
            }

            SettingsSection("启动") {
                Toggle("登录时启动右键助手", isOn: launchEnabledBinding)

                Toggle("后台启动时保持静默", isOn: Binding(
                    get: { isSilentLaunchEnabled },
                    set: saveSilentLaunch
                ))
            }

            SettingsSection("通知") {
                Toggle("显示成功通知", isOn: Binding(
                    get: { showsSuccessNotifications },
                    set: saveSuccessNotifications
                ))
                Text("默认仅通知操作失败。通知不播放声音，并遵循系统通知设置和专注模式。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    Text(notifications.authorizationSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(notifications.authorizationStatus == .notDetermined ? "允许通知…" : "通知设置…") {
                        if notifications.authorizationStatus == .notDetermined {
                            Task { await notifications.requestAuthorization() }
                        } else {
                            notifications.openSystemSettings()
                        }
                    }
                    .disabled(notifications.isRequestingAuthorization)
                }
            }

            SettingsSection("关于") {
                LabeledContent("版本") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("许可") {
                    Text("MIT")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("隐私") {
                    Text("完全离线 · 无广告 · 无遥测")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: session.revision, initial: true) {
            guard session.isVisible else { return }
            refresh()
        }
    }

    private func refresh() {
        Task { await notifications.refreshAuthorization() }
        isLaunchEnabled = LaunchServiceManager.shared.isEnabled
        isSilentLaunchEnabled = SharedStorageManager.shared.getBool(
            forKey: LaunchPresentationPolicy.silentLaunchKey,
            defaultValue: true
        )
        showsSuccessNotifications = SharedStorageManager.shared.getBool(
            forKey: SharedStorageManager.Keys.enableSuccessNotifications,
            defaultValue: false
        )
    }

    private func saveSilentLaunch(_ enabled: Bool) {
        guard SharedStorageManager.shared.setBool(
            enabled,
            forKey: LaunchPresentationPolicy.silentLaunchKey
        ) else {
            showConfigurationSaveFailure("静默启动")
            return
        }
        isSilentLaunchEnabled = enabled
    }

    private func saveSuccessNotifications(_ enabled: Bool) {
        guard SharedStorageManager.shared.setBool(
            enabled,
            forKey: SharedStorageManager.Keys.enableSuccessNotifications
        ) else {
            showConfigurationSaveFailure("成功提示")
            return
        }
        showsSuccessNotifications = enabled
        if enabled {
            Task { await notifications.requestAuthorization() }
        } else {
            notifications.clearSuccessNotifications()
        }
    }
}
