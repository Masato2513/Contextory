import SwiftUI

/// 设置窗口复用期间只保留一份检测结果；隐藏窗口不启动检测，也不累积页面回调。
@MainActor
final class SettingsSession: ObservableObject {
    @Published private(set) var snapshot: RightClickMenuHealthSnapshot?
    @Published private(set) var revision = 0
    private(set) var isVisible = false
    private var generation = 0
    private var isRefreshing = false
    private var needsRefresh = false
    private let queue = DispatchQueue(
        label: "io.github.masato2513.Contextory.settings-refresh",
        qos: .utility,
        autoreleaseFrequency: .workItem
    )

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        generation += 1
        if visible {
            refresh(afterChanges: true)
        } else {
            needsRefresh = false
        }
    }

    /// 激活与显示事件合并；设置或修复完成后，最多追加一次检测以取得最新状态。
    func refresh(afterChanges: Bool = false) {
        guard isVisible else { return }
        guard !isRefreshing else {
            needsRefresh = needsRefresh || afterChanges
            return
        }
        isRefreshing = true
        needsRefresh = false
        let currentGeneration = generation
        queue.async { [weak self] in
            let result = makeRightClickMenuHealthSnapshot()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                guard self.isVisible else { return }
                if self.generation == currentGeneration {
                    self.snapshot = result
                    self.revision += 1
                }
                if self.needsRefresh {
                    self.refresh()
                }
            }
        }
    }
}

/// 三个固定设置页使用普通滚动布局，避免为简单表单创建列表和导航控制器。
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
