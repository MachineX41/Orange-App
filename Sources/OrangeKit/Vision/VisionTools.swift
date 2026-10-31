import CoreImage
import Foundation
import Vision

public enum TextRecognizer {
    public static func text(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}

public struct BarcodeHit: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var source: String
    public var page: Int?
    public var symbology: String
    public var payload: String
}

public enum BarcodeReader {
    public static func scan(_ image: CGImage, source: String, page: Int? = nil) throws -> [BarcodeHit] {
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue else { return nil }
            let symbology = observation.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            return BarcodeHit(source: source, page: page, symbology: symbology, payload: payload)
        }
    }

    public static func scan(url: URL) throws -> [BarcodeHit] {
        let name = url.lastPathComponent
        var hits: [BarcodeHit] = []
        if Catalog.kind(for: url) == .pdf {
            try PDFToolkit.forEachPage(of: url, scale: 2) { index, image in
                hits += (try? scan(image, source: name, page: index + 1)) ?? []
            }
        } else {
            hits = try scan(ImageEngine.load(url), source: name)
        }
        var seen = Set<String>()
        return hits.filter { seen.insert("\($0.page ?? 0)|\($0.payload)").inserted }
    }
}

/// Finds regions worth redacting. Rects are normalized with a top-left origin.
public enum RegionFinder {
    public static func faces(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).map { topLeft($0.boundingBox, padding: 0.18) }
    }

    public static func text(in image: CGImage) throws -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).map { topLeft($0.boundingBox, padding: 0.06) }
    }

    static func topLeft(_ box: CGRect, padding: CGFloat) -> CGRect {
        let padX = box.width * padding
        let padY = box.height * padding
        let rect = CGRect(x: box.minX - padX, y: 1 - box.maxY - padY, width: box.width + padX * 2, height: box.height + padY * 2)
        return rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

public enum BackgroundRemover {
    public static func cutout(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw OrangeError.noSubject
        }
        let buffer = try result.generateMaskedImage(
            ofInstances: result.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        let output = CIImage(cvPixelBuffer: buffer)
        return try CoreImageKit.cgImage(output, extent: output.extent)
    }
}
