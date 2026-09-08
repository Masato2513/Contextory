import AppKit
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

    /// Office 文件和 PDF 必须包含有效结构；普通文本类保持真正的空文件。
    public var defaultEmptyBytes: Data {
        switch self {
        case .docx, .xlsx, .pptx:
            if let url = Bundle.main.url(
                forResource: "blank",
                withExtension: rawValue,
                subdirectory: "Templates"
            ), let data = try? Data(contentsOf: url) {
                return data
            }
            AppLog.error("缺少 Templates/blank.\(rawValue)", category: .action)
            return Data()
        case .pdf:
            return Self.blankPDFData
        case .txt, .md, .json:
            return Data()
        }
    }

    private static let blankPDFData: Data = {
        var pdf = "%PDF-1.4\n"
        let objects = [
            "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
            "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
            "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>\nendobj\n",
            "4 0 obj\n<< /Length 0 >>\nstream\nendstream\nendobj\n"
        ]
        var offsets: [Int] = []
        for object in objects {
            offsets.append(pdf.utf8.count)
            pdf += object
        }
        let xrefOffset = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\n"
        pdf += "startxref\n\(xrefOffset)\n%%EOF\n"
        return pdf.data(using: .ascii) ?? Data()
    }()
}

/// 文件创建的纯逻辑边界，便于独立验证命名、冲突处理和输入安全。
public enum NewFileCreator {
    public static func destinationDirectory(for targetURL: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return targetURL
        }
        return targetURL.deletingLastPathComponent()
    }

    public static func normalizedCustomFileName(_ input: String) -> String? {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains(":"),
              !name.contains("\0") else {
            return nil
        }
        return name
    }

    public static func requiresStructuredTemplate(_ fileName: String) -> Bool {
        let pathExtension = (fileName as NSString).pathExtension.lowercased()
        return ["docx", "xlsx", "pptx", "pdf"].contains(pathExtension)
    }

    /// 同名时从 2 开始递增，例如“新建文件.md”→“新建文件 2.md”。
    public static func availableURL(
        in directory: URL,
        requestedName: String,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> URL {
        var candidate = directory.appendingPathComponent(requestedName)
        guard fileExists(candidate.path) else { return candidate }

        let nsName = requestedName as NSString
        let pathExtension = nsName.pathExtension
        let stem = pathExtension.isEmpty ? requestedName : nsName.deletingPathExtension
        var counter = 2
        repeat {
            let numberedName = pathExtension.isEmpty
                ? "\(stem) \(counter)"
                : "\(stem) \(counter).\(pathExtension)"
            candidate = directory.appendingPathComponent(numberedName)
            counter += 1
        } while fileExists(candidate.path)
        return candidate
    }

    @discardableResult
    public static func create(
        targetURL: URL,
        requestedName: String,
        data: Data
    ) throws -> URL {
        let directory = destinationDirectory(for: targetURL)
        let finalURL = availableURL(in: directory, requestedName: requestedName)
        try data.write(to: finalURL, options: .atomic)
        return finalURL
    }
}

/// 七种常用格式的一键创建动作。
public final class NewFileAction: MenuAction, @unchecked Sendable {
    public let actionId: String
    public let localizedTitle: String
    public let iconName: String?
    public let fileType: SupportedFileType
    private let customTemplateURL: URL?

    public init(fileType: SupportedFileType, customTemplateURL: URL? = nil) {
        self.fileType = fileType
        self.customTemplateURL = customTemplateURL
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

    public func execute(targetURLs: [URL]) -> Bool {
        guard let targetURL = targetURLs.first else { return false }
        let fileData: Data
        if let customTemplateURL,
           FileManager.default.fileExists(atPath: customTemplateURL.path),
           let data = try? Data(contentsOf: customTemplateURL) {
            fileData = data
        } else {
            fileData = fileType.defaultEmptyBytes
        }

        if fileType == .docx || fileType == .xlsx || fileType == .pptx {
            guard fileData.starts(with: Data([0x50, 0x4B])) else {
                SharedHUDManager.show(
                    title: "模板不可用",
                    content: "未找到有效的 \(fileType.extensionName.uppercased()) 模板，未创建文件",
                    isSuccess: false
                )
                return false
            }
        }

        return createAndReveal(
            targetURL: targetURL,
            requestedName: "新建文件.\(fileType.extensionName)",
            data: fileData
        )
    }
}

/// 低频格式入口：用户输入完整文件名和后缀，创建真正的空文件。
public final class OtherNewFileAction: MenuAction, @unchecked Sendable {
    public let actionId = "io.github.masato2513.Contextory.action.newfile.other"
    public let localizedTitle = "其他…"
    public let iconName: String? = "doc.badge.plus"

    public func execute(targetURLs: [URL]) -> Bool {
        guard let targetURL = targetURLs.first else { return false }
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                promptAndCreate(targetURL: targetURL) == .succeeded
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                promptAndCreate(targetURL: targetURL) == .succeeded
            }
        }
    }

    public func submit(
        targetURLs: [URL],
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission {
        guard let targetURL = targetURLs.first else {
            completion(.failed)
            return .rejected
        }
        DispatchQueue.main.async { [self] in
            completion(promptAndCreate(targetURL: targetURL))
        }
        return .accepted
    }

    @MainActor
    private func promptAndCreate(targetURL: URL) -> ActionCompletionStatus {
        let input = NSTextField(string: "")
        input.placeholderString = "例如：test.csv、config.yaml、.env"
        input.frame = NSRect(x: 0, y: 0, width: 340, height: 24)

        let alert = NSAlert()
        alert.messageText = "新建其他文件"
        alert.informativeText = "请输入完整文件名，可自行填写任意后缀。"
        alert.alertStyle = .informational
        alert.accessoryView = input
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
        guard let fileName = NewFileCreator.normalizedCustomFileName(input.stringValue) else {
            SharedHUDManager.show(
                title: "文件名无效",
                content: "请输入不包含 / 或 : 的完整文件名",
                isSuccess: false
            )
            return .failed
        }
        guard !NewFileCreator.requiresStructuredTemplate(fileName) else {
            SharedHUDManager.show(
                title: "需要有效模板",
                content: "Office 和 PDF 请使用菜单中的专用创建项",
                isSuccess: false
            )
            return .failed
        }
        return createAndReveal(
            targetURL: targetURL,
            requestedName: fileName,
            data: Data()
        ) ? .succeeded : .failed
    }
}

@discardableResult
private func createAndReveal(
    targetURL: URL,
    requestedName: String,
    data: Data
) -> Bool {
    do {
        let finalURL = try NewFileCreator.create(
            targetURL: targetURL,
            requestedName: requestedName,
            data: data
        )
        SharedHUDManager.show(
            title: "新建成功",
            content: "已生成并高亮：\(finalURL.lastPathComponent)",
            isSuccess: true
        )
        NewFileRevealer.reveal(finalURL)
        return true
    } catch {
        AppLog.error("创建文件失败：\(error.localizedDescription)", category: .action)
        SharedHUDManager.show(
            title: "新建失败",
            content: "请检查目录写入权限",
            isSuccess: false
        )
        return false
    }
}

/// 高亮新建文件。Finder 的公开 `NSWorkspace` API 会为桌面打开一个新窗口，
/// 因此在兼容菜单启用时，桌面文件改为直接设置 Finder 桌面的选中项。
private enum NewFileRevealer {
    private static let desktopSelectionDelay: TimeInterval = 0.15
    private static let desktopSelectionScriptSource = """
    on selectDesktopItem(posixPath)
        tell application "Finder"
            set createdItem to (POSIX file posixPath as alias)
            activate
            select window of desktop
            set selection to {createdItem}
        end tell
    end selectDesktopItem
    """

    /// Open Scripting Architecture 的四字符事件码。直接使用系统 ABI 常量值，
    /// 避免仅为四个常量链接 Carbon umbrella framework。
    private enum AppleEventCode {
        static let appleScriptSuite: AEEventClass = 0x61736372 // 'ascr'
        static let subroutineEvent: AEEventID = 0x70736272 // 'psbr'
        static let subroutineName: AEKeyword = 0x736E616D // 'snam'
        static let directObject: AEKeyword = 0x2D2D2D2D // '----'
    }

    static func reveal(_ fileURL: URL) {
        let useDesktopSelection = isDesktopItem(fileURL)
            && SharedStorageManager.shared.getBool(
                forKey: SharedStorageManager.Keys.finderCompatibilityMenuEnabled,
                defaultValue: false
            )

        if useDesktopSelection {
            // iCloud/File Provider 同步桌面有时不会在写入完成的同一轮事件循环中
            // 立即刷新图标；只延迟执行一次，不引入轮询或常驻任务。
            DispatchQueue.main.asyncAfter(deadline: .now() + desktopSelectionDelay) {
                selectOnFinderDesktop(fileURL)
            }
            return
        }

        DispatchQueue.main.async {
            NSWorkspace.shared.selectFile(
                fileURL.path,
                inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path
            )
        }
    }

    private static func isDesktopItem(_ fileURL: URL) -> Bool {
        guard let desktopURL = try? FileManager.default.url(
            for: .desktopDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return false
        }

        let parentURL = fileURL.deletingLastPathComponent()
        return normalizedDirectoryURL(parentURL) == normalizedDirectoryURL(desktopURL)
    }

    private static func normalizedDirectoryURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func selectOnFinderDesktop(_ fileURL: URL) {
        guard let script = NSAppleScript(source: desktopSelectionScriptSource) else {
            AppLog.error("初始化 Finder 桌面高亮脚本失败", category: .action)
            return
        }

        let event = NSAppleEventDescriptor(
            eventClass: AppleEventCode.appleScriptSuite,
            eventID: AppleEventCode.subroutineEvent,
            targetDescriptor: nil,
            returnID: AEReturnID(-1),
            transactionID: AETransactionID(0)
        )
        event.setParam(
            NSAppleEventDescriptor(string: "selectDesktopItem"),
            forKeyword: AppleEventCode.subroutineName
        )

        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: fileURL.path), at: 1)
        event.setParam(arguments, forKeyword: AppleEventCode.directObject)

        var errorInfo: NSDictionary?
        _ = script.executeAppleEvent(event, error: &errorInfo)
        if let errorInfo {
            // 桌面选中失败时不要回退到 NSWorkspace，否则会重新打开 Desktop 窗口。
            AppLog.error("高亮 Finder 桌面文件失败：\(errorInfo)", category: .action)
        }
    }
}
