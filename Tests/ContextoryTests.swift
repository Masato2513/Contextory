import Foundation
import XCTest
@testable import ContextoryCore

final class ContextoryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testRegistryContainsOnlyRequestedActionsInMenuOrder() {
        let actions = DefaultActionRegistry.makeActions()

        XCTAssertEqual(actions.map(\.actionId), [
            "io.github.masato2513.Contextory.action.newfile.txt",
            "io.github.masato2513.Contextory.action.newfile.md",
            "io.github.masato2513.Contextory.action.newfile.json",
            "io.github.masato2513.Contextory.action.newfile.docx",
            "io.github.masato2513.Contextory.action.newfile.xlsx",
            "io.github.masato2513.Contextory.action.newfile.pptx",
            "io.github.masato2513.Contextory.action.newfile.pdf",
            "io.github.masato2513.Contextory.action.newfile.other",
            "io.github.masato2513.Contextory.action.copy-path"
        ])
        XCTAssertEqual(actions.map(\.localizedTitle), [
            "文本文件 (.txt)",
            "Markdown (.md)",
            "JSON (.json)",
            "Word 文档 (.docx)",
            "Excel 表格 (.xlsx)",
            "PowerPoint 演示文稿 (.pptx)",
            "PDF 文档 (.pdf)",
            "其他…",
            "复制路径"
        ])
    }

    func testDefaultNameStartsAtTwoWhenColliding() throws {
        let first = try NewFileCreator.create(
            targetURL: temporaryDirectory,
            requestedName: "新建文件.md",
            data: Data()
        )
        let second = try NewFileCreator.create(
            targetURL: temporaryDirectory,
            requestedName: "新建文件.md",
            data: Data()
        )
        let third = try NewFileCreator.create(
            targetURL: temporaryDirectory,
            requestedName: "新建文件.md",
            data: Data()
        )

        XCTAssertEqual(first.lastPathComponent, "新建文件.md")
        XCTAssertEqual(second.lastPathComponent, "新建文件 2.md")
        XCTAssertEqual(third.lastPathComponent, "新建文件 3.md")
    }

    func testOtherFileKeepsUserProvidedNameAndCreatesEmptyFile() throws {
        let url = try NewFileCreator.create(
            targetURL: temporaryDirectory,
            requestedName: "test.csv",
            data: Data()
        )

        XCTAssertEqual(url.lastPathComponent, "test.csv")
        XCTAssertEqual(try Data(contentsOf: url), Data())
    }

    func testOtherFileCollisionPreservesExtension() throws {
        try Data().write(to: temporaryDirectory.appendingPathComponent("config.yaml"))
        let url = try NewFileCreator.create(
            targetURL: temporaryDirectory,
            requestedName: "config.yaml",
            data: Data()
        )

        XCTAssertEqual(url.lastPathComponent, "config 2.yaml")
    }

    func testOtherFileNameValidationAllowsDotFilesAndRejectsPaths() {
        XCTAssertEqual(NewFileCreator.normalizedCustomFileName(" test.xml "), "test.xml")
        XCTAssertEqual(NewFileCreator.normalizedCustomFileName(".env"), ".env")
        XCTAssertNil(NewFileCreator.normalizedCustomFileName(""))
        XCTAssertNil(NewFileCreator.normalizedCustomFileName("../escape.txt"))
        XCTAssertNil(NewFileCreator.normalizedCustomFileName("folder/file.txt"))
        XCTAssertNil(NewFileCreator.normalizedCustomFileName("bad:name.txt"))
        XCTAssertTrue(NewFileCreator.requiresStructuredTemplate("report.docx"))
        XCTAssertTrue(NewFileCreator.requiresStructuredTemplate("slides.PPTX"))
        XCTAssertTrue(NewFileCreator.requiresStructuredTemplate("manual.pdf"))
        XCTAssertFalse(NewFileCreator.requiresStructuredTemplate("config.yaml"))
    }

    func testPlainTextTypesUseTrueEmptyFiles() {
        XCTAssertEqual(SupportedFileType.txt.defaultEmptyBytes, Data())
        XCTAssertEqual(SupportedFileType.md.defaultEmptyBytes, Data())
        XCTAssertEqual(SupportedFileType.json.defaultEmptyBytes, Data())
    }

    func testPDFTemplateHasValidHeaderAndTrailer() {
        let data = SupportedFileType.pdf.defaultEmptyBytes

        XCTAssertTrue(data.starts(with: Data("%PDF-".utf8)))
        XCTAssertTrue(data.contains(Data("%%EOF".utf8)))
    }

    func testCustomOfficeTemplatesAreWrittenWithoutModification() throws {
        let officeTypes: [SupportedFileType] = [.docx, .xlsx, .pptx]

        for fileType in officeTypes {
            let bundledTemplate = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/Templates/blank.\(fileType.extensionName)")
            let template = try Data(contentsOf: bundledTemplate)
            let templateURL = temporaryDirectory
                .appendingPathComponent("template.\(fileType.extensionName)")
            try template.write(to: templateURL)
            let outputDirectory = temporaryDirectory
                .appendingPathComponent("output-\(fileType.extensionName)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            let action = NewFileAction(fileType: fileType, customTemplateURL: templateURL)
            XCTAssertTrue(action.execute(targetURLs: [outputDirectory]))

            let output = outputDirectory
                .appendingPathComponent(fileType.defaultFileName)
            XCTAssertEqual(try Data(contentsOf: output), template)
        }
    }

    func testDispatcherRegistersAndExecutesFixedAction() throws {
        let action = ProbeAction()
        let dispatcher = ActionDispatcher()
        dispatcher.register(action: action)

        XCTAssertTrue(dispatcher.dispatch(
            actionId: action.actionId,
            targetURLs: [temporaryDirectory],
            invocationKind: .container
        ))
        XCTAssertTrue(action.didExecute)
    }

    func testLegacyEventDefaultsToItemsInvocation() throws {
        let data = #"{"id":"1","createdAt":1,"actionId":"test","paths":["/tmp/a"]}"#
            .data(using: .utf8)!

        let event = try JSONDecoder().decode(SharedActionEvent.self, from: data)

        XCTAssertEqual(event.schemaVersion, 1)
        XCTAssertEqual(event.invocationKind, .items)
    }
}

private final class ProbeAction: MenuAction {
    let actionId = "test.probe"
    let localizedTitle = "Probe"
    let iconName: String? = nil
    private(set) var didExecute = false

    func execute(targetURLs: [URL]) -> Bool {
        didExecute = true
        return true
    }
}
