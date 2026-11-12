import AppKit
import PDFKit
import XCTest
@testable import OrangeKit

final class ZZDeckProbe: XCTestCase {
    func testProbeDecks() throws {
        guard let list = ProcessInfo.processInfo.environment["ORANGE_PROBE"] else { throw XCTSkip("no probe") }
        let out = URL(fileURLWithPath: "/tmp/oprobe", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        OutputLocation.customDirectory = out
        defer { OutputLocation.customDirectory = nil }
        for path in list.split(separator: "|").map(String.init) {
            let start = Date()
            let pdf = try PresentationConverter.convert(URL(fileURLWithPath: path))
            let doc = try XCTUnwrap(PDFDocument(url: pdf))
            print("PROBE \(pdf.lastPathComponent) pages=\(doc.pageCount) time=\(Date().timeIntervalSince(start))")
            let limit = Int(ProcessInfo.processInfo.environment["ORANGE_PAGES"] ?? "6") ?? 6
            for i in 0..<min(doc.pageCount, limit) {
                guard let page = doc.page(at: i) else { continue }
                let b = page.bounds(for: .mediaBox)
                let img = page.thumbnail(of: NSSize(width: 960, height: 960 * b.height / b.width), for: .mediaBox)
                let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
                let png = rep.representation(using: .png, properties: [:])!
                try png.write(to: out.appendingPathComponent("\(pdf.deletingPathExtension().lastPathComponent)-\(i + 1).png"))
            }
        }
    }
}
