import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrangeKit

func makeTempDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orange-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
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
        let followsTurkish = Locale.preferredLanguages.first?.hasPrefix("tr") == true
        XCTAssertEqual(Lang.isTurkish, followsTurkish)
        XCTAssertEqual(Lang.t("Save", "Kaydet"), followsTurkish ? "Kaydet" : "Save")
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
