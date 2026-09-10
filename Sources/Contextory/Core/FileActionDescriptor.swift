import Foundation

/// Finder 菜单中提供的一键新建文件类型。
public enum SupportedFileType: String, CaseIterable, Codable, Identifiable, Sendable {
    case txt
    case md
    case json
    case docx
    case xlsx
    case pptx
    case pdf

    public var id: String { rawValue }
    public var extensionName: String { rawValue }

    /// 按文件用途命名；同名编号交给 NewFileCreator 统一处理。
    public var defaultFileName: String {
        switch self {
        case .txt: return "新建文本.txt"
        case .md: return "新建 Markdown 文档.md"
        case .json: return "新建 JSON 数据.json"
        case .docx: return "新建文档.docx"
        case .xlsx: return "新建表格.xlsx"
        case .pptx: return "新建演示文稿.pptx"
        case .pdf: return "新建 PDF 文档.pdf"
        }
    }

    public var displayName: String {
        switch self {
        case .txt: return "文本文件 (.txt)"
        case .md: return "Markdown (.md)"
        case .json: return "JSON (.json)"
        case .docx: return "Word 文档 (.docx)"
        case .xlsx: return "Excel 表格 (.xlsx)"
        case .pptx: return "PowerPoint 演示文稿 (.pptx)"
        case .pdf: return "PDF 文档 (.pdf)"
        }
    }

}

/// Finder 菜单只需要这些值；执行器、通知与文件模板仅由宿主加载。
public struct FileActionDescriptor: Equatable, Sendable {
    public let actionId: String
    public let localizedTitle: String
    public let iconName: String

    public static let other = FileActionDescriptor(
        actionId: "io.github.masato2513.Contextory.action.newfile.other",
        localizedTitle: "其他…",
        iconName: "doc.badge.plus"
    )
    public static let copyPath = FileActionDescriptor(
        actionId: "io.github.masato2513.Contextory.action.copy-path",
        localizedTitle: "复制路径",
        iconName: "doc.on.clipboard"
    )
    public static let newFileActions = SupportedFileType.allCases.map { Self(fileType: $0) } + [other]
    public static let all = newFileActions + [copyPath]

    public init(fileType: SupportedFileType) {
        actionId = "io.github.masato2513.Contextory.action.newfile.\(fileType.rawValue)"
        localizedTitle = fileType.displayName
        switch fileType {
        case .txt: iconName = "doc.text"
        case .md: iconName = "doc.text.fill"
        case .json: iconName = "curlybraces"
        case .docx: iconName = "doc.richtext"
        case .xlsx: iconName = "tablecells.fill"
        case .pptx: iconName = "rectangle.stack.fill"
        case .pdf: iconName = "doc.fill"
        }
    }

    private init(actionId: String, localizedTitle: String, iconName: String) {
        self.actionId = actionId
        self.localizedTitle = localizedTitle
        self.iconName = iconName
    }
}
