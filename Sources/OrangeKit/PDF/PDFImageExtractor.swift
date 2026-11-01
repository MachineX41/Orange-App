import CoreGraphics
import Foundation
import PDFKit

public enum PDFImageExtractor {
    /// Finds raster image placements per page and saves each as a PNG crop.
    /// Returns relative paths (`<base>-images/p<N>-<i>.png`) aligned with pages,
    /// so Markdown export can reference real local files. Tiny placements
    /// (<64pt) are skipped.
    public static func extractImages(from url: URL, into directory: URL, baseName: String) throws -> [[String]] {
        guard let document = PDFDocument(url: url) else {
            throw OrangeError.unreadable(url.lastPathComponent)
        }
        var perPage: [[String]] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let cgPage = page.pageRef
            else {
                perPage.append([])
                continue
            }
            let boxes = imageBoxes(on: cgPage)
            guard !boxes.isEmpty else {
                perPage.append([])
                continue
            }
            let folder = directory.appendingPathComponent("\(baseName)-images", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let full = PDFToolkit.pageImage(page, scale: 2) else {
                perPage.append([])
                continue
            }
            var paths: [String] = []
            let mediaBox = page.bounds(for: .mediaBox)
            for (i, box) in boxes.enumerated() {
                // PDF points (bottom-left) -> pixels (top-left).
                let px = box.origin.x / mediaBox.width * CGFloat(full.width)
                let py = (mediaBox.height - box.maxY) / mediaBox.height * CGFloat(full.height)
                let pw = box.width / mediaBox.width * CGFloat(full.width)
                let ph = box.height / mediaBox.height * CGFloat(full.height)
                let rect = CGRect(x: px, y: py, width: pw, height: ph).integral
                    .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
                guard rect.width >= 64, rect.height >= 64,
                      let crop = full.cropping(to: rect)
                else { continue }
                let name = "p\(index + 1)-\(i + 1).png"
                try ImageEngine.write(crop, to: folder.appendingPathComponent(name), as: .png, quality: 1.0)
                paths.append("\(baseName)-images/\(name)")
            }
            perPage.append(paths)
        }
        return perPage
    }

    /// Placement boxes of image XObjects via CGPDFScanner operator callbacks.
    /// Tracks the CTM through q/Q/cm and records each Do's unit-square mapping.
    private static func imageBoxes(on page: CGPDFPage) -> [CGRect] {
        final class State {
            var stack: [CGAffineTransform] = [.identity]
            var boxes: [CGRect] = []
            // swiftlint:disable:next force_unwrapping
            var page: CGPDFPage!
        }
        let state = State()
        state.page = page
        let context = Unmanaged.passUnretained(state).toOpaque()

        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let state = Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
            state.stack.append(state.stack.last ?? .identity)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let state = Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
            if state.stack.count > 1 { state.stack.removeLast() }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let state = Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
            var a: CGPDFReal = 0, b: CGPDFReal = 0, c: CGPDFReal = 0
            var d: CGPDFReal = 0, e: CGPDFReal = 0, f: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &a), CGPDFScannerPopNumber(scanner, &b),
                  CGPDFScannerPopNumber(scanner, &c), CGPDFScannerPopNumber(scanner, &d),
                  CGPDFScannerPopNumber(scanner, &e), CGPDFScannerPopNumber(scanner, &f)
            else { return }
            let m = CGAffineTransform(a: CGFloat(a), b: CGFloat(b), c: CGFloat(c), d: CGFloat(d), tx: CGFloat(e), ty: CGFloat(f))
            state.stack[state.stack.count - 1] = (state.stack.last ?? .identity).concatenating(m)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let state = Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let cname = name.map({ String(cString: $0) }) else { return }
            // Only image XObjects: check the resource dictionary.
            guard let pageDict = state.page.dictionary,
                  let xobjects = ocrPdfDictGetDict(pageDict, "Resources").flatMap({ ocrPdfDictGetDict($0, "XObject") }),
                  let stream = ocrPdfDictGetStream(xobjects, cname),
                  let dict = CGPDFStreamGetDictionary(stream),
                  ocrPdfNameEquals(ocrPdfDictGetObject(dict, "Subtype"), "Image")
            else { return }
            let ctm = state.stack.last ?? .identity
            // Do paints the unit square through the CTM.
            let box = CGRect(x: 0, y: 0, width: 1, height: 1).applying(ctm)
            let standardized = CGRect(x: min(box.minX, box.maxX), y: min(box.minY, box.maxY),
                                      width: abs(box.width), height: abs(box.height))
            if standardized.width >= 64, standardized.height >= 64 {
                state.boxes.append(standardized)
            }
        }
        let cs = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(cs) }
        let scanner = CGPDFScannerCreate(cs, table, context)
        defer { CGPDFScannerRelease(scanner) }
        CGPDFScannerScan(scanner)
        return state.boxes
    }
}

private func ocrPdfDictGetObject(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFObjectRef? {
        var obj: CGPDFObjectRef?
        return CGPDFDictionaryGetObject(dict, key, &obj) ? obj : nil
    }

private func ocrPdfDictGetDict(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
        var obj: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dict, key, &obj), let obj else { return nil }
        var out: CGPDFDictionaryRef?
        return CGPDFObjectGetValue(obj, .dictionary, &out) ? out : nil
    }

private func ocrPdfDictGetStream(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFStreamRef? {
        var obj: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dict, key, &obj), let obj else { return nil }
        var out: CGPDFStreamRef?
        return CGPDFObjectGetValue(obj, .stream, &out) ? out : nil
    }

private func ocrPdfNameEquals(_ obj: CGPDFObjectRef?, _ name: String) -> Bool {
        guard let obj else { return false }
        var out: UnsafePointer<CChar>?
        guard CGPDFObjectGetValue(obj, .name, &out), let cstr = out else { return false }
        return String(cString: cstr) == name
    }

