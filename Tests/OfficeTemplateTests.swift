import Foundation
import XCTest
@testable import ContextoryCore

final class OfficeTemplateTests: XCTestCase {
    func testDefaultFileNamesAndCollisionNumberingForEveryType() {
        let expected: [SupportedFileType: String] = [
            .txt: "新建文本.txt", .md: "新建 Markdown 文档.md",
            .json: "新建 JSON 数据.json", .docx: "新建文档.docx",
            .xlsx: "新建表格.xlsx", .pptx: "新建演示文稿.pptx",
            .pdf: "新建 PDF 文档.pdf"
        ]
        for type in SupportedFileType.allCases {
            XCTAssertEqual(type.defaultFileName, expected[type])
            let directory = URL(fileURLWithPath: "/tmp/contextory-naming")
            let stem = (type.defaultFileName as NSString).deletingPathExtension
            let occupied = [type.defaultFileName, "\(stem) 2.\(type.extensionName)"]
            let result = NewFileCreator.availableURL(
                in: directory, requestedName: type.defaultFileName,
                fileExists: { occupied.contains(URL(fileURLWithPath: $0).lastPathComponent) }
            )
            XCTAssertEqual(result.lastPathComponent, "\(stem) 3.\(type.extensionName)")
        }
    }

    func testOfficeTemplatesHaveReadableXMLAndResolvedRelationships() throws {
        for (suffix, mainPart) in [("docx", "word/document.xml"), ("xlsx", "xl/workbook.xml"), ("pptx", "ppt/presentation.xml")] {
            let root = try unpackTemplate(suffix)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(mainPart).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("[Content_Types].xml").path))
            let paths = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            for path in paths where path.hasSuffix(".xml") || path.hasSuffix(".rels") {
                let url = root.appendingPathComponent(path)
                let xml = try parseXML(url)
                if path.hasSuffix(".rels") {
                    for relationship in xml.attributes(named: "Relationship") where relationship["TargetMode"] != "External" {
                        let target = try XCTUnwrap(relationship["Target"])
                        let destination = resolve(target, relationshipURL: url, root: root)
                        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "缺少模板关联：\(suffix)/\(path) → \(target)")
                    }
                }
            }
        }
    }

    func testPowerPointTemplateHasSlideSizeMasterLayoutAndTheme() throws {
        let root = try unpackTemplate("pptx")
        let presentation = root.appendingPathComponent("ppt/presentation.xml")
        let xml = try parseXML(presentation)
        let size = try XCTUnwrap(xml.attributes(named: "sldSz").first)
        XCTAssertGreaterThan(Int(size["cx"] ?? "") ?? 0, 0)
        XCTAssertGreaterThan(Int(size["cy"] ?? "") ?? 0, 0)
        XCTAssertFalse(xml.attributes(named: "sldMasterId").isEmpty)
        let slides = try relatedParts(of: presentation, type: "slide", root: root)
        XCTAssertEqual(slides.count, 1, "默认模板应保留一页空白幻灯片")
        XCTAssertFalse(try relatedParts(of: presentation, type: "slideMaster", root: root).isEmpty)
        for slide in slides {
            let layouts = try relatedParts(of: slide, type: "slideLayout", root: root)
            XCTAssertFalse(layouts.isEmpty, "幻灯片必须关联版式")
            for layout in layouts {
                let masters = try relatedParts(of: layout, type: "slideMaster", root: root)
                XCTAssertFalse(masters.isEmpty, "版式必须关联母版")
                for master in masters {
                    XCTAssertFalse(try relatedParts(of: master, type: "theme", root: root).isEmpty)
                }
            }
        }
    }

    private func unpackTemplate(_ suffix: String) throws -> URL {
        let template = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Templates/blank.\(suffix)")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ContextoryTemplateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let result = SystemReloader.runCommand(executablePath: "/usr/bin/unzip", arguments: ["-qq", template.path, "-d", root.path])
        XCTAssertTrue(result.isSuccess, result.standardError)
        return root
    }

    private func parseXML(_ url: URL) throws -> TemplateXML {
        let parser = XMLParser(data: try Data(contentsOf: url))
        let delegate = TemplateXML()
        parser.delegate = delegate
        XCTAssertTrue(parser.parse(), "无效 XML：\(url.lastPathComponent)")
        return delegate
    }

    private func relatedParts(of part: URL, type: String, root: URL) throws -> [URL] {
        let relationships = part.deletingLastPathComponent()
            .appendingPathComponent("_rels").appendingPathComponent(part.lastPathComponent + ".rels")
        return try parseXML(relationships).attributes(named: "Relationship")
            .filter { $0["Type"]?.hasSuffix("/" + type) == true }
            .map { resolve(try XCTUnwrap($0["Target"]), relationshipURL: relationships, root: root) }
    }

    private func resolve(_ target: String, relationshipURL: URL, root: URL) -> URL {
        let decoded = target.removingPercentEncoding ?? target
        let base = decoded.hasPrefix("/") ? root : relationshipURL.deletingLastPathComponent().deletingLastPathComponent()
        return base.appendingPathComponent(decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded).standardizedFileURL
    }
}

private final class TemplateXML: NSObject, XMLParserDelegate {
    private var elements: [(String, [String: String])] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String]) {
        elements.append((elementName.components(separatedBy: ":").last ?? elementName, attributeDict))
    }

    func attributes(named name: String) -> [[String: String]] {
        elements.filter { $0.0 == name }.map(\.1)
    }
}
