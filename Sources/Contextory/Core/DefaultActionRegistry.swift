import Foundation

/// 宿主内置动作的注册清单；Finder 扩展只读取对应的 FileActionDescriptor。
public enum DefaultActionRegistry {
    public static func makeActions() -> [MenuAction] {
        let commonActions: [MenuAction] = SupportedFileType.allCases.map {
            NewFileAction(fileType: $0)
        }
        return commonActions + [OtherNewFileAction(), CopyPathAction()]
    }

    @discardableResult
    public static func registerAll(into dispatcher: ActionDispatcher = .shared) -> [MenuAction] {
        let actions = makeActions()
        actions.forEach(dispatcher.register(action:))
        return actions
    }
}
