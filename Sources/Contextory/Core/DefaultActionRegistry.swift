import Foundation

/// 内置动作的唯一清单。Host、FinderSync、设置页和测试均从这里取得相同实例集合。
public enum DefaultActionRegistry {
    public static func makeActions() -> [MenuAction] {
        let commonActions: [MenuAction] = SupportedFileType.allCases.map {
            NewFileAction(fileType: $0)
        }
        return commonActions + [OtherNewFileAction()]
    }

    @discardableResult
    public static func registerAll(into dispatcher: ActionDispatcher = .shared) -> [MenuAction] {
        let actions = makeActions()
        actions.forEach(dispatcher.register(action:))
        return actions
    }
}
