import SwiftUI

/// 侧边栏导航条目
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "overview"
    case permissions = "permissions"
    case diagnostics = "diagnostics"

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .permissions: return "Finder"
        case .diagnostics: return "诊断"
        }
    }

    var iconName: String {
        switch self {
        case .overview: return "gearshape"
        case .permissions: return "folder"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

public struct ContentView: View {
    @State private var selectedTab: SidebarItem = .overview
    @EnvironmentObject private var session: SettingsSession

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SidebarItem.allCases) { item in
                    Button {
                        selectedTab = item
                    } label: {
                        Label(item.title, systemImage: item.iconName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(selectedTab == item ? Color.accentColor.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityAddTraits(selectedTab == item ? .isSelected : [])
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 180)
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selectedTab.title)
                        .font(.system(size: 20, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                detailContent
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 850, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            session.refresh()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .overview:
            OverviewSettingsView()
        case .permissions:
            PermissionsSettingsView()
        case .diagnostics:
            DiagnosticsSettingsView()
        }
    }
}
