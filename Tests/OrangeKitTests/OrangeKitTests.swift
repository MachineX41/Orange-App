import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrangeKit

final class CatalogTests: XCTestCase {
    func testImageAndVideoHaveNoSharedTarget() {
        let shared = Catalog.commonConvertTargets(for: [.image, .video])
        XCTAssertTrue(shared.isEmpty)
    }

    func testImagesShareRasterTargets() {
        let shared = Catalog.commonConvertTargets(for: [.image, .image])
        XCTAssertTrue(shared.contains(.jpeg))
        XCTAssertTrue(shared.contains(.pdf))
        XCTAssertFalse(shared.contains(.mp4))
    }

    func testKindDetection() {
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.JPG")), .image)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.mp4")), .video)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.mp3")), .audio)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.pdf")), .pdf)
        XCTAssertEqual(Catalog.kind(for: URL(fileURLWithPath: "/tmp/a.zip")), .archive)
    }
}

final class WheelLayoutTests: XCTestCase {
    func testCardinalIndexes() {
        let layout = WheelLayout(
            center: CGPoint(x: 200, y: 200),
            ringRadius: 100,
            innerRadius: 40,
            outerRadius: 160,
            count: 4
        )
        XCTAssertEqual(layout.index(at: CGPoint(x: 200, y: 100)), 0)
        XCTAssertEqual(layout.index(at: CGPoint(x: 300, y: 200)), 1)
        XCTAssertEqual(layout.index(at: CGPoint(x: 200, y: 300)), 2)
        XCTAssertEqual(layout.index(at: CGPoint(x: 100, y: 200)), 3)
        XCTAssertNil(layout.index(at: CGPoint(x: 200, y: 200)))
        XCTAssertNil(layout.index(at: CGPoint(x: 200, y: 10)))
    }

    func testPointForTopItem() {
        let layout = WheelLayout(
            center: CGPoint(x: 200, y: 200),
            ringRadius: 100,
            innerRadius: 40,
            outerRadius: 160,
            count: 4
        )
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
        let normalized = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        let pixels = CropMath.pixelRect(normalizedTopLeft: normalized, imageSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(pixels, CGRect(x: 0, y: 50, width: 200, height: 50))
    }

    func testSelectionOutsideImageClips() {
        let normalized = CropMath.normalizedRect(
            selection: CGRect(x: -20, y: 40, width: 80, height: 40),
            imageSize: CGSize(width: 200, height: 100),
            viewSize: CGSize(width: 200, height: 200)
        )
        XCTAssertEqual(normalized.origin.x, 0, accuracy: 0.001)
        XCTAssertGreaterThan(normalized.width, 0)
    }
}

final class PageRangeTests: XCTestCase {
    func testParsesCommaRanges() throws {
        let ranges = try PDFToolkit.parsePageSelection("1-3, 5", pageCount: 8)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0], 1...3)
        XCTAssertEqual(ranges[1], 5...5)
    }

    func testAllKeyword() throws {
        let ranges = try PDFToolkit.parsePageSelection("hepsi", pageCount: 4)
        XCTAssertEqual(ranges, [1...4])
    }

    func testRejectsReversedRange() {
        XCTAssertThrowsError(try PDFToolkit.parsePageSelection("8-5", pageCount: 8))
    }
}

final class UniqueDestinationTests: XCTestCase {
    func testAvoidsExistingName() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = directory.appendingPathComponent("Photo.jpg")
        try Data([0xFF, 0xD8]).write(to: first)
        let next = UniqueDestination.url(in: directory, baseName: "Photo", extension: "jpg")
        XCTAssertEqual(next.lastPathComponent, "Photo 2.jpg")
    }
}

final class ImageTranscoderTests: XCTestCase {
    func testConvertsPNGToJPEG() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("swatch.png")
        try writeSwatch(to: source, width: 12, height: 8)
        let output = try ImageTranscoder().convert(
            ImageRequest(source: source, operation: .original, format: .jpeg, quality: 0.9, directory: directory)
        )
        let data = try Data(contentsOf: output)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        let rotated = try ImageTranscoder().convert(
            ImageRequest(source: source, operation: .rotateClockwise(90), format: .png, quality: 1, directory: directory)
        )
        let image = try ImageTranscoder().loadOriented(rotated)
        XCTAssertEqual(image.width, 8)
        XCTAssertEqual(image.height, 12)
    }

    private func writeSwatch(to url: URL, width: Int, height: Int) throws {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            XCTFail("context")
            return
        }
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let painted = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            XCTFail("destination")
            return
        }
        _ = image
        CGImageDestinationAddImage(destination, painted, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

final class ArchiveToolkitTests: XCTestCase {
    func testZipRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let note = directory.appendingPathComponent("hello.txt")
        try Data("orange".utf8).write(to: note)
        let zip = try ArchiveToolkit.zip(urls: [note], into: directory)
        let extracted = try ArchiveToolkit.unzip(archive: zip, into: directory)
        let found = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
            .contains { $0.lastPathComponent == "hello.txt" }
        XCTAssertTrue(found)
    }
}
