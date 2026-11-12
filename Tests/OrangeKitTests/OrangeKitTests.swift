import AppKit
import CoreGraphics
import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrangeKit

func makeTempDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orange-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func sample(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat, bounds: CGRect) -> (red: Int, green: Int, blue: Int) {
    let px = min(max(Int(x / bounds.width * CGFloat(rep.pixelsWide)), 0), max(rep.pixelsWide - 1, 0))
    let py = min(max(Int(y / bounds.height * CGFloat(rep.pixelsHigh)), 0), max(rep.pixelsHigh - 1, 0))
    let color = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) ?? .clear
    return (Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
}

func makeDeck(in directory: URL) throws -> URL {
    let root = directory.appendingPathComponent("deck", isDirectory: true)
    for folder in ["ppt/_rels", "ppt/slides/_rels", "ppt/slides", "ppt/media", "ppt/theme"] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <p:sldIdLst>
        <p:sldId id="256" r:id="rId1"/>
        <p:sldId id="257" r:id="rId2"/>
      </p:sldIdLst>
      <p:sldSz cx="12192000" cy="6858000"/>
    </p:presentation>
    """.write(to: root.appendingPathComponent("ppt/presentation.xml"), atomically: true, encoding: .utf8)
    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/>
    </Relationships>
    """.write(to: root.appendingPathComponent("ppt/_rels/presentation.xml.rels"), atomically: true, encoding: .utf8)
    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <p:cSld>
        <p:spTree>
          <p:sp>
            <p:spPr>
              <a:xfrm><a:off x="1270000" y="1270000"/><a:ext cx="2540000" cy="1270000"/></a:xfrm>
              <a:prstGeom prst="rect"/>
              <a:solidFill><a:srgbClr val="F26B1D"/></a:solidFill>
            </p:spPr>
          </p:sp>
          <p:pic>
            <p:blipFill><a:blip r:embed="rId1"/></p:blipFill>
            <p:spPr>
              <a:xfrm><a:off x="5080000" y="400000"/><a:ext cx="1270000" cy="1270000"/></a:xfrm>
            </p:spPr>
          </p:pic>
          <p:sp>
            <p:spPr>
              <a:xfrm><a:off x="1270000" y="3000000"/><a:ext cx="8000000" cy="1400000"/></a:xfrm>
            </p:spPr>
            <p:txBody>
              <a:bodyPr/>
              <a:p><a:r><a:rPr sz="3200" b="1"><a:solidFill><a:srgbClr val="112233"/></a:solidFill></a:rPr><a:t>Orange slide</a:t></a:r></a:p>
            </p:txBody>
          </p:sp>
        </p:spTree>
      </p:cSld>
    </p:sld>
    """.write(to: root.appendingPathComponent("ppt/slides/slide1.xml"), atomically: true, encoding: .utf8)
    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/pixel.png"/>
    </Relationships>
    """.write(to: root.appendingPathComponent("ppt/slides/_rels/slide1.xml.rels"), atomically: true, encoding: .utf8)
    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
      <p:cSld>
        <p:spTree>
          <p:grpSp>
            <p:grpSpPr>
              <a:xfrm>
                <a:off x="457200" y="457200"/>
                <a:ext cx="8000000" cy="2000000"/>
                <a:chOff x="0" y="0"/>
                <a:chExt cx="8000000" cy="2000000"/>
              </a:xfrm>
            </p:grpSpPr>
            <p:sp>
              <p:spPr>
                <a:xfrm><a:off x="0" y="0"/><a:ext cx="7000000" cy="1200000"/></a:xfrm>
                <a:solidFill><a:schemeClr val="accent1"><a:lumMod val="80000"/></a:schemeClr></a:solidFill>
              </p:spPr>
              <p:txBody>
                <a:bodyPr/>
                <a:p><a:r><a:rPr sz="2400"/><a:t>Grouped line</a:t></a:r></a:p>
              </p:txBody>
            </p:sp>
          </p:grpSp>
        </p:spTree>
      </p:cSld>
    </p:sld>
    """.write(to: root.appendingPathComponent("ppt/slides/slide2.xml"), atomically: true, encoding: .utf8)
    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
      <a:themeElements>
        <a:clrScheme name="Orange">
          <a:dk1><a:srgbClr val="111111"/></a:dk1>
          <a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
          <a:accent1><a:srgbClr val="F26B1D"/></a:accent1>
        </a:clrScheme>
        <a:fontScheme name="Office">
          <a:majorFont><a:latin typeface="Helvetica"/></a:majorFont>
          <a:minorFont><a:latin typeface="Helvetica"/></a:minorFont>
        </a:fontScheme>
      </a:themeElements>
    </a:theme>
    """.write(to: root.appendingPathComponent("ppt/theme/theme1.xml"), atomically: true, encoding: .utf8)
    try ImageEngine.write(try makeSwatch(width: 8, height: 8), to: root.appendingPathComponent("ppt/media/pixel.png"), as: .png, quality: 1)

    let deck = directory.appendingPathComponent("deck.pptx")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--norsrc", root.path, deck.path]
    let error = Pipe()
    process.standardError = error
    process.standardOutput = Pipe()
    try process.run()
    process.waitUntilExit()
    let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    if process.terminationStatus != 0 { throw OrangeError.toolFailed(message) }
    return deck
}

func makeSwatch(width: Int, height: Int) throws -> CGImage {
    try ImageEngine.render(width: width, height: height) { context in
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
    }
}

final class CatalogTests: XCTestCase {
    func testKindDetection() {
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.JPG")), .image)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.mp4")), .video)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.mp3")), .audio)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.pdf")), .pdf)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.zip")), .archive)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.docx")), .document)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.pptx")), .document)
        XCTAssertEqual(Catalog.convertTargets(for: URL(fileURLWithPath: "/tmp/a.pptx")), [.pdf])
    }

    func testTargetsExcludeOwnFormat() {
        let targets = Catalog.convertTargets(for: URL(fileURLWithPath: "/tmp/a.jpeg"))
        XCTAssertFalse(targets.contains(.jpeg))
        XCTAssertTrue(targets.contains(.png))
        XCTAssertTrue(targets.contains(.pdf))
    }

    func testMixedSelectionHasNoSharedTarget() {
        let shared = Catalog.commonConvertTargets(for: [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.mp4")])
        XCTAssertTrue(shared.isEmpty)
    }

    func testMultiFileToolsRequireBatchSupport() {
        let one = Catalog.commonTools(for: [URL(fileURLWithPath: "/tmp/a.pdf")])
        XCTAssertFalse(one.contains(.mergePDF))
        XCTAssertTrue(one.contains(.splitPDF))
        let two = Catalog.commonTools(for: [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.pdf")])
        XCTAssertTrue(two.contains(.mergePDF))
        XCTAssertFalse(two.contains(.splitPDF))
    }
}

final class WheelLayoutTests: XCTestCase {
    let layout = WheelLayout(center: CGPoint(x: 200, y: 200), ringRadius: 100, innerRadius: 40, outerRadius: 160, count: 4)

    func testCardinalIndexes() {
        XCTAssertEqual(layout.index(at: CGPoint(x: 200, y: 100)), 0)
        XCTAssertEqual(layout.index(at: CGPoint(x: 300, y: 200)), 1)
        XCTAssertEqual(layout.index(at: CGPoint(x: 200, y: 300)), 2)
        XCTAssertEqual(layout.index(at: CGPoint(x: 100, y: 200)), 3)
        XCTAssertEqual(layout.index(at: CGPoint(x: 190, y: 95)), 0)
        XCTAssertNil(layout.index(at: CGPoint(x: 200, y: 200)))
        XCTAssertNil(layout.index(at: CGPoint(x: 200, y: 10)))
    }

    func testPointForTopItem() {
        let point = layout.point(for: 0)
        XCTAssertEqual(point.x, 200, accuracy: 0.001)
        XCTAssertEqual(point.y, 100, accuracy: 0.001)
    }
}

final class CropMathTests: XCTestCase {
    func testAspectFitCentersShortImage() {
        let fitted = CropMath.fittedRect(imageSize: CGSize(width: 200, height: 100), in: CGSize(width: 200, height: 200))
        XCTAssertEqual(fitted, CGRect(x: 0, y: 50, width: 200, height: 100))
    }

    func testTopHalfMapsToUpperPixels() {
        let pixels = CropMath.pixelRect(normalizedTopLeft: CGRect(x: 0, y: 0, width: 1, height: 0.5), imageSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(pixels, CGRect(x: 0, y: 50, width: 200, height: 50))
    }
}

final class PDFCompressTests: XCTestCase {
    func testHeavyPageShrinksWithoutLosingThePage() throws {
        let directory = try makeTempDirectory()
        let width = 1400
        let height = 2000
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var state: UInt32 = 0x12345678
        for index in stride(from: 0, to: pixels.count, by: 4) {
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[index] = UInt8(truncatingIfNeeded: state >> 16)
            pixels[index + 1] = UInt8(truncatingIfNeeded: state >> 8)
            pixels[index + 2] = UInt8(truncatingIfNeeded: state)
        }
        let image = try pixels.withUnsafeBytes { raw -> CGImage in
            let space = CGColorSpaceCreateDeviceRGB()
            guard let provider = CGDataProvider(data: Data(raw) as CFData),
                  let image = CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                  ) else { throw OrangeError.writeFailed("image") }
            return image
        }
        let source = directory.appendingPathComponent("scan.pdf")
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(url: source as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &page, nil) else {
            throw OrangeError.writeFailed(source.lastPathComponent)
        }
        context.beginPDFPage(nil)
        context.interpolationQuality = .none
        context.draw(image, in: page)
        context.endPDFPage()
        context.closePDF()

        let compressed = try PDFToolkit.compress(url: source)
        let before = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.intValue ?? 0
        let after = (try FileManager.default.attributesOfItem(atPath: compressed.path)[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(before, 1_000_000)
        XCTAssertLessThan(after, before / 2)
        XCTAssertEqual(try PDFToolkit.pageCount(of: compressed), 1)
        let document = try XCTUnwrap(PDFDocument(url: compressed))
        let preview = try XCTUnwrap(document.page(at: 0)?.thumbnail(of: CGSize(width: 40, height: 56), for: .mediaBox))
        XCTAssertGreaterThan(preview.size.width, 10)
    }
}

final class PageRangeTests: XCTestCase {
    func testParsesCommaRanges() throws {
        let ranges = try PDFToolkit.parsePageSelection("1-3, 5, 7-", pageCount: 8)
        XCTAssertEqual(ranges, [1...3, 5...5, 7...8])
    }

    func testAllKeyword() throws {
        XCTAssertEqual(try PDFToolkit.parsePageSelection("hepsi", pageCount: 4), [1...4])
    }

    func testRejectsReversedRange() {
        XCTAssertThrowsError(try PDFToolkit.parsePageSelection("8-5", pageCount: 8))
    }
}

final class UniqueDestinationTests: XCTestCase {
    func testAvoidsExistingName() throws {
        let directory = try makeTempDirectory()
        try Data([0xFF, 0xD8]).write(to: directory.appendingPathComponent("Photo.jpg"))
        XCTAssertEqual(UniqueDestination.url(in: directory, baseName: "Photo", extension: "jpg").lastPathComponent, "Photo 2.jpg")
    }
}

final class ImageEngineTests: XCTestCase {
    func testConvertRotateAndFormats() throws {
        let directory = try makeTempDirectory()
        let source = directory.appendingPathComponent("swatch.png")
        try ImageEngine.write(makeSwatch(width: 12, height: 8), to: source, as: .png, quality: 1)

        let jpeg = try ImageEngine.convert(ImageRequest(source: source, format: .jpeg, directory: directory))
        XCTAssertEqual(Array(try Data(contentsOf: jpeg).prefix(2)), [0xFF, 0xD8])

        let rotated = try ImageEngine.convert(ImageRequest(source: source, operation: .rotateClockwise(90), format: .png, directory: directory, suffix: "r"))
        let image = try ImageEngine.load(rotated)
        XCTAssertEqual(image.width, 8)
        XCTAssertEqual(image.height, 12)

        let pdf = try ImageEngine.convert(ImageRequest(source: source, format: .pdf, directory: directory))
        XCTAssertEqual(try PDFToolkit.pageCount(of: pdf), 1)
    }

    func testCropKeepsTopHalf() throws {
        let image = try makeSwatch(width: 20, height: 20)
        let top = try ImageEngine.transform(image, .cropNormalized(CGRect(x: 0, y: 0, width: 1, height: 0.5)))
        XCTAssertEqual(top.width, 20)
        XCTAssertEqual(top.height, 10)
    }

    func testCompositingPipelines() throws {
        let image = try makeSwatch(width: 100, height: 60)
        var style = BackdropStyle()
        style.aspect = .square
        let framed = try Backdrop.render(image, style: style)
        XCTAssertEqual(framed.width, framed.height)
        XCTAssertGreaterThan(framed.width, 100)

        let redacted = try Redactor.render([CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)], style: .pixelate, image: image)
        XCTAssertEqual(redacted.width, 100)

        let marks = [
            Mark(tool: .arrow, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)], color: RGBA(1, 0, 0), width: 0.02),
            Mark(tool: .text, points: [CGPoint(x: 0.2, y: 0.2)], color: RGBA(1, 1, 1), width: 0.02, text: "Hi")
        ]
        XCTAssertEqual(try AnnotationRenderer.render(marks, onto: image).height, 60)

        let collage = try Collage.render([image, image, image], style: CollageStyle())
        XCTAssertEqual(collage.width, 2400)

        var adjustments = PhotoAdjustments()
        adjustments.exposure = 0.5
        adjustments.warmth = 30
        XCTAssertEqual(try PhotoAdjust.render(adjustments, image: image).width, 100)
    }
}

final class DocumentAndPDFTests: XCTestCase {
    func testDocumentRoundTrip() throws {
        let directory = try makeTempDirectory()
        let note = directory.appendingPathComponent("note.txt")
        try "Orange document\nSecond line".write(to: note, atomically: true, encoding: .utf8)
        let docx = try DocumentConverter.convert(note, to: .docx)
        XCTAssertTrue(try DocumentConverter.load(docx).string.contains("Orange document"))
        let pdf = try DocumentConverter.convert(note, to: .pdf)
        XCTAssertTrue(try PDFToolkit.text(of: pdf).contains("Second line"))

        let merged = try PDFToolkit.merge(urls: [pdf, pdf], into: directory)
        XCTAssertEqual(try PDFToolkit.pageCount(of: merged), 2)
        let organized = try PDFToolkit.organize(url: merged, pages: [PageEdit(source: 1, rotation: 90)])
        XCTAssertEqual(try PDFToolkit.pageCount(of: organized), 1)
        let parts = try PDFToolkit.split(url: merged, mode: .everyPage, into: directory)
        XCTAssertEqual(parts.count, 2)
        let images = try PDFToolkit.toImages(url: pdf, format: .png)
        XCTAssertEqual(images.first?.pathExtension, "png")
    }

    func testPowerPointBecomesPDF() throws {
        let directory = try makeTempDirectory()
        let deck = try makeDeck(in: directory)
        let pdf = try PresentationConverter.convert(deck)
        XCTAssertEqual(pdf.pathExtension, "pdf")
        XCTAssertEqual(try PDFToolkit.pageCount(of: pdf), 2)
        let text = try PDFToolkit.text(of: pdf)
        XCTAssertTrue(text.contains("Orange slide"))
        XCTAssertTrue(text.contains("Grouped line"))

        let document = try XCTUnwrap(PDFDocument(url: pdf))
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 960, accuracy: 0.2)
        XCTAssertEqual(bounds.height, 540, accuracy: 0.2)

        let thumb = page.thumbnail(of: NSSize(width: bounds.width, height: bounds.height), for: .mediaBox)
        let rep = try XCTUnwrap(thumb.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let shape = sample(rep, x: 200, y: 150, bounds: bounds)
        XCTAssertGreaterThan(shape.red, 200, "shape \(shape)")
        XCTAssertLessThan(shape.blue, 80, "shape \(shape)")

        let source = try XCTUnwrap(NSImage(contentsOf: directory.appendingPathComponent("deck/ppt/media/pixel.png")))
        let sourceRep = try XCTUnwrap(source.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let sourceTop = sample(sourceRep, x: 4, y: 1, bounds: CGRect(x: 0, y: 0, width: 8, height: 8))
        let photo = sample(rep, x: 430, y: 50, bounds: bounds)
        XCTAssertLessThan(abs(photo.red - sourceTop.red), 30, "photo \(photo) source \(sourceTop)")
        XCTAssertLessThan(abs(photo.green - sourceTop.green), 30, "photo \(photo) source \(sourceTop)")
        XCTAssertLessThan(abs(photo.blue - sourceTop.blue), 30, "photo \(photo) source \(sourceTop)")
    }

    func testMediaLinkDiscovery() {
        let html = #"<html><head><meta property="og:video" content="/clip.mp4?a=1&amp;b=2"></head></html>"#
        let link = LinkDownloader.mediaLink(in: html, base: URL(string: "https://example.com/page")!)
        XCTAssertEqual(link?.absoluteString, "https://example.com/clip.mp4?a=1&b=2")
    }
}

final class ArchiveToolkitTests: XCTestCase {
    func testZipRoundTrip() throws {
        let directory = try makeTempDirectory()
        let note = directory.appendingPathComponent("hello.txt")
        try Data("orange".utf8).write(to: note)
        let zip = try ArchiveToolkit.zip(urls: [note], into: directory)
        let extracted = try ArchiveToolkit.extract(archive: zip, into: directory)
        let files = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { $0.lastPathComponent == "hello.txt" })
    }
}

final class MediaPipelineTests: XCTestCase {
    func testAudioAndVideoPipeline() async throws {
        let directory = try makeTempDirectory()
        OutputLocation.customDirectory = directory
        defer { OutputLocation.customDirectory = nil }

        let rate = 44_100.0
        let tone = (0..<Int(rate * 2)).map { index -> Float in
            index < Int(rate * 0.3) ? 0 : 0.4 * Float(sin(2 * .pi * 440 * Double(index) / rate))
        }
        let wav = directory.appendingPathComponent("tone.wav")
        try AudioClip(sampleRate: rate, channels: [tone, tone]).write(to: wav)

        let clip = try await AudioClip.load(wav)
        XCTAssertEqual(clip.duration, 2, accuracy: 0.05)
        XCTAssertEqual(clip.silenceBounds().lowerBound, 0.3, accuracy: 0.03)
        XCTAssertEqual(clip.remixed(toMono: true, gains: [1]).channelCount, 1)
        XCTAssertEqual(AudioClip.decibels(clip.normalized(.peak, target: -1).peak), -1, accuracy: 0.1)
        let bleeped = clip.bleeped([0.5...1.0], tone: false)
        XCTAssertLessThan(bleeped.trimmed(0.6, 0.9).peak, 0.001)

        let m4a = try await AudioEngine.convert(wav, to: .m4a, progress: nil)
        let encoded = try await AudioClip.load(m4a)
        XCTAssertEqual(encoded.duration, 2, accuracy: 0.1)

        var style = VisualizerStyle()
        style.size = CGSize(width: 320, height: 320)
        let video = try await Visualizer.render(audio: wav, style: style, progress: nil)
        let info = try await VideoEditor.info(video)
        XCTAssertTrue(info.hasVideo)
        XCTAssertTrue(info.hasAudio)
        XCTAssertEqual(info.duration, 2, accuracy: 0.15)

        let trimmed = try await VideoEditor.trim(video, range: 0.5...1.5, progress: nil)
        let trimmedInfo = try await VideoEditor.info(trimmed)
        XCTAssertEqual(trimmedInfo.duration, 1, accuracy: 0.15)

        let gif = try await GIFMaker.make(from: video, progress: nil)
        XCTAssertGreaterThan(CGImageSourceGetCount(CGImageSourceCreateWithURL(gif as CFURL, nil)!), 10)

        let cropped = try await VideoEditor.crop(video, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), progress: nil)
        let croppedInfo = try await VideoEditor.info(cropped)
        XCTAssertEqual(croppedInfo.size.width, 160, accuracy: 2)

        let fast = try await VideoEditor.changeSpeed(video, factor: 2, progress: nil)
        let fastInfo = try await VideoEditor.info(fast)
        XCTAssertEqual(fastInfo.duration, 1, accuracy: 0.15)

        let joined = try await VideoEditor.join([video, trimmed], progress: nil)
        let joinedInfo = try await VideoEditor.info(joined)
        XCTAssertEqual(joinedInfo.duration, 3, accuracy: 0.2)

        let muted = try await VideoEditor.mute(video, progress: nil)
        let mutedInfo = try await VideoEditor.info(muted)
        XCTAssertFalse(mutedInfo.hasAudio)

        let frames = try await VideoEditor.exportFrames(video, times: [0.5], format: .png, progress: nil)
        XCTAssertEqual(frames.first?.pathExtension, "png")

        let before = try video.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let converted = try await VideoEditor.convert(video, to: .mp4, progress: nil)
        let after = try converted.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let convertedInfo = try await VideoEditor.info(converted)
        XCTAssertLessThan(after, before / 2)
        XCTAssertEqual(convertedInfo.size.width, info.size.width, accuracy: 2)
        XCTAssertEqual(convertedInfo.size.height, info.size.height, accuracy: 2)
        XCTAssertEqual(convertedInfo.duration, info.duration, accuracy: 0.2)
        XCTAssertTrue(convertedInfo.hasAudio)

        let bloated = VideoEditor.compactVideoBitrate(pixels: 1920 * 1080, fps: 30, sourceBitsPerSecond: 20_000_000, hevc: true)
        XCTAssertEqual(bloated, 7_464_960)
        let efficient = VideoEditor.compactVideoBitrate(pixels: 1920 * 1080, fps: 30, sourceBitsPerSecond: 4_000_000, hevc: true)
        XCTAssertEqual(efficient, 3_200_000)
        XCTAssertLessThan(efficient, 4_000_000)

        let clean = try await MetadataKit.strip(video, progress: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clean.path))
    }
}

final class DownloadProgressTests: XCTestCase {
    func testProgressFollowsTheNewestPercent() {
        var reader = LinkDownloader.DownloadProgressReader()
        let first = reader.feed("ORANGEPROG:0.0\rORANGEPROG:12.5\r")
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first[0], 0, accuracy: 0.0001)
        XCTAssertEqual(first[1], 0.125, accuracy: 0.0001)
        let split = reader.feed("ORANGEPROG:40") + reader.feed(".5\n[download]  80.0% of 1.00MiB\n")
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split[0], 0.405, accuracy: 0.0001)
        XCTAssertEqual(split[1], 0.8, accuracy: 0.0001)
    }

    func testColoredAndUnknownPercents() {
        var reader = LinkDownloader.DownloadProgressReader()
        let updates = reader.feed("\u{1B}[0;94m[download]\u{1B}[0m   7.5% of 2.00MiB\n[download]  N/A% of Unknown\n")
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0], 0.075, accuracy: 0.0001)
        let finished = reader.finish()
        XCTAssertNil(finished.progress)
        XCTAssertTrue(finished.paths.isEmpty)
    }

    func testOutputPathIsSeparateFromProgress() {
        var reader = LinkDownloader.DownloadProgressReader()
        XCTAssertTrue(reader.feed("ORANGEPROG:NA\nORANGE:/tmp/clip.mp4\n").isEmpty)
        let finished = reader.finish()
        XCTAssertNil(finished.progress)
        XCTAssertEqual(finished.paths, ["/tmp/clip.mp4"])
    }

    func testSecondFileContinuesTheRing() {
        var reader = LinkDownloader.DownloadProgressReader()
        let values = reader.feed("ORANGEPROG:100\nORANGEPROG:0.3\nORANGEPROG:50\n")
        XCTAssertEqual(values[0], 0.99, accuracy: 0.001)
        XCTAssertGreaterThan(values[1], 0.8)
        XCTAssertGreaterThan(values[2], values[1])
    }
}

final class WebPTests: XCTestCase {
    func testWebPIsWritableAndRoundTrips() throws {
        XCTAssertTrue(ImageCapabilities.canWrite(.webp))
        XCTAssertTrue(Catalog.convertTargets(for: URL(fileURLWithPath: "/tmp/a.jpg")).contains(.webp))
        XCTAssertFalse(Catalog.convertTargets(for: URL(fileURLWithPath: "/tmp/a.webp")).contains(.webp))

        let directory = try makeTempDirectory()
        let source = directory.appendingPathComponent("swatch.png")
        try ImageEngine.write(try makeSwatch(width: 64, height: 40), to: source, as: .png, quality: 1)
        let output = try ImageEngine.convert(ImageRequest(source: source, format: .webp, quality: 0.9, directory: directory))
        XCTAssertEqual(output.pathExtension, "webp")

        let data = try Data(contentsOf: output)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self), "WEBP")
        let decoded = try ImageEngine.load(output)
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 40)
    }

    func testTransparentWebPKeepsAlpha() throws {
        let image = try ImageEngine.render(width: 8, height: 8) { context in
            context.clear(CGRect(x: 0, y: 0, width: 8, height: 8))
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try WebPEncoder.encode(image, quality: 1, lossless: true)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertNotEqual(decoded.alphaInfo, .none)
    }
}

final class LanguageTests: XCTestCase {
    func testChoiceOverridesTheSystemLanguage() {
        let previous = Lang.choice
        defer { Lang.choice = previous }

        Lang.choice = .english
        XCTAssertFalse(Lang.isTurkish)
        XCTAssertEqual(Lang.t("Save", "Kaydet"), "Save")

        Lang.choice = .turkish
        XCTAssertTrue(Lang.isTurkish)
        XCTAssertEqual(Lang.t("Save", "Kaydet"), "Kaydet")

        Lang.choice = .system
        let followsTurkish = Lang.systemPrefersTurkish()
        XCTAssertEqual(Lang.isTurkish, followsTurkish)
        XCTAssertEqual(Lang.t("Save", "Kaydet"), followsTurkish ? "Kaydet" : "Save")
    }

    func testSystemLanguageFallsBackToEnglish() {
        XCTAssertTrue(Lang.systemPrefersTurkish(["tr-TR"]))
        XCTAssertTrue(Lang.systemPrefersTurkish(["de", "tr"]))
        XCTAssertFalse(Lang.systemPrefersTurkish(["en-GB"]))
        XCTAssertFalse(Lang.systemPrefersTurkish(["en", "tr"]))
        XCTAssertFalse(Lang.systemPrefersTurkish(["de", "fr"]))
        XCTAssertFalse(Lang.systemPrefersTurkish([]))
    }
}

final class CodeActionTests: XCTestCase {
    func testWebLinks() {
        XCTAssertEqual(CodeAction.parse("https://www.apple.com/tr/").destination, "apple.com")
        XCTAssertEqual(CodeAction.parse("www.example.com/menu"), .web(URL(string: "https://www.example.com/menu")!))
        XCTAssertEqual(CodeAction.parse("example.org"), .web(URL(string: "https://example.org")!))
        XCTAssertTrue(CodeAction.parse("http://example.com").isInsecure)
        XCTAssertFalse(CodeAction.parse("https://example.com").isInsecure)
    }

    func testContactSchemes() {
        XCTAssertEqual(CodeAction.parse("mailto:ali@example.com").destination, "ali@example.com")
        XCTAssertEqual(CodeAction.parse("ali@example.com"), .email(URL(string: "mailto:ali@example.com")!))
        XCTAssertEqual(CodeAction.parse("tel:+905551112233").destination, "+905551112233")
        guard case .message(let sms) = CodeAction.parse("SMSTO:+905551112233:Merhaba") else { return XCTFail() }
        XCTAssertEqual(sms.scheme, "sms")
        guard case .email(let mail) = CodeAction.parse("MATMSG:TO:ali@example.com;SUB:Selam;BODY:Nasılsın;;") else { return XCTFail() }
        XCTAssertTrue(mail.absoluteString.hasPrefix("mailto:ali@example.com?"))
        guard case .map(let map) = CodeAction.parse("geo:41.0082,28.9784") else { return XCTFail() }
        XCTAssertEqual(map.host(), "maps.apple.com")
    }

    func testWifi() {
        XCTAssertEqual(CodeAction.parse("WIFI:T:WPA;S:Ev Ağı;P:gizli\\;123;;"), .wifi(ssid: "Ev Ağı", password: "gizli;123"))
        XCTAssertEqual(CodeAction.parse("WIFI:T:nopass;S:Kafe;;"), .wifi(ssid: "Kafe", password: nil))
    }

    func testUnsafeOrPlainPayloadsStayText() {
        XCTAssertEqual(CodeAction.parse("javascript:alert(1)"), .text)
        XCTAssertEqual(CodeAction.parse("file:///etc/passwd"), .text)
        XCTAssertEqual(CodeAction.parse("x-apple.systempreferences:com.apple"), .text)
        XCTAssertEqual(CodeAction.parse("4006381333931"), .text)
        XCTAssertEqual(CodeAction.parse("Merhaba dünya"), .text)
        XCTAssertEqual(CodeAction.parse("https://localhost"), .text)
        XCTAssertEqual(CodeAction.parse("v1.2"), .text)
    }
}
