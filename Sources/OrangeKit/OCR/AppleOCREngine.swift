import CoreGraphics
import Foundation
import Vision

/// Apple on-device OCR. Text mode uses accurate recognition; document mode
/// extracts transcript/paragraphs/lists/tables from `RecognizeDocumentsRequest`.
/// Compute stays OS-managed — never advertised as forced Metal.
public struct AppleOCREngine: OCREngine {
    public init() {}

    public func recognize(_ image: CGImage, options: OCROptions) async throws -> OCRPageContent {
        try Task.checkCancellation()
        let started = ContinuousClock.now
        let content: OCRPageContent
        switch options.mode {
        case .text:
            content = try await recognizeText(image, options: options)
        case .document:
            if #available(macOS 26.0, *) {
                content = try await recognizeDocuments(image, options: options)
            } else {
                content = try await recognizeText(image, options: options)
            }
        }
        try Task.checkCancellation()
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return OCRPageContent(
            text: content.text,
            markdown: content.markdown,
            blocks: content.blocks,
            tables: content.tables,
            actualCompute: .appleManaged,
            durationSeconds: seconds,
            truncated: false
        )
    }

    private func recognizeText(_ image: CGImage, options: OCROptions) async throws -> OCRPageContent {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        try applyLanguages(options.languageIdentifiers, toText: &request)
        try Task.checkCancellation()
        let observations: [RecognizedTextObservation] = try await request.perform(on: image)
        try Task.checkCancellation()
        let blocks = observations.map { observation in
            let box = observation.boundingBox
            let rect = CGRect(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height)
            return OCRTextBlock(text: observation.transcript, bounds: Self.topLeft(rect))
        }
        let text = blocks.map { $0.text }.joined(separator: "\n")
        return OCRPageContent(text: text, blocks: blocks, actualCompute: .appleManaged)
    }
    @available(macOS 26.0, *)
    private func recognizeDocuments(_ image: CGImage, options: OCROptions) async throws -> OCRPageContent {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        try applyLanguages(options.languageIdentifiers, toDocuments: &request)
        try Task.checkCancellation()
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        let renderer = OCRDocumentRenderer()
        return renderer.render(observations, mode: options.mode)
    }

    private func applyLanguages(_ identifiers: [String], toText request: inout RecognizeTextRequest) throws {
        guard !identifiers.isEmpty else { return }
        let supported = request.supportedRecognitionLanguages
        let wanted = identifiers.compactMap { Locale.Language(identifier: $0) }
        let matched = wanted.filter { want in supported.contains { $0.minimalIdentifier == want.minimalIdentifier } }
        guard !wanted.isEmpty else { return }
        guard !matched.isEmpty else {
            throw OrangeError.unsupported("No requested OCR language is supported: \(identifiers.joined(separator: ", "))")
        }
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = matched
    }

    @available(macOS 26.0, *)
    private func applyLanguages(_ identifiers: [String], toDocuments request: inout RecognizeDocumentsRequest) throws {
        guard !identifiers.isEmpty else { return }
        let supported = request.supportedRecognitionLanguages
        let wanted = identifiers.compactMap { Locale.Language(identifier: $0) }
        guard !wanted.isEmpty else { return }
        let matched = wanted.filter { want in supported.contains { $0.minimalIdentifier == want.minimalIdentifier } }
        guard !matched.isEmpty else {
            throw OrangeError.unsupported("No requested OCR language is supported: \(identifiers.joined(separator: ", "))")
        }
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.recognitionLanguages = matched
    }

    /// Vision uses bottom-left origin; OCR blocks use top-left.
    static func topLeft(_ box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

/// Turns structured document observations into plain text + Markdown without
/// duplicating content (paragraph text feeding a table/list is emitted once).
struct OCRDocumentRenderer: Sendable {
    func render(_ observations: [DocumentObservation], mode: OCRMode) -> OCRPageContent {
        var textParts: [String] = []
        var markdownParts: [String] = []
        var blocks: [OCRTextBlock] = []
        var tables: [OCRTable] = []
        for observation in observations {
            let container = observation.document
            let emitted = renderContainer(container, textParts: &textParts, markdownParts: &markdownParts, blocks: &blocks, tables: &tables)
            _ = emitted
        }
        let text = textParts.joined(separator: mode == .document ? "\n\n" : "\n")
        let markdown = mode == .document ? markdownParts.joined(separator: "\n\n") : nil
        return OCRPageContent(text: text, markdown: markdown, blocks: blocks, tables: tables, actualCompute: .appleManaged)
    }

    @discardableResult
    private func renderContainer(
        _ container: DocumentObservation.Container,
        textParts: inout [String],
        markdownParts: inout [String],
        blocks: inout [OCRTextBlock],
        tables: inout [OCRTable]
    ) -> Bool {
        // Title first, then the full-text transcript as the paragraph source.
        if let title = container.title, !title.transcript.isEmpty {
            textParts.append(title.transcript)
            markdownParts.append("# \(escapeHeading(title.transcript))")
            blocks.append(OCRTextBlock(text: title.transcript))
        }
        // Paragraphs carry the running text; tables/lists below reference the same
        // spans but are emitted as structure instead of repeated prose.
        var paragraphTexts = Set<String>()
        for paragraph in container.paragraphs where !paragraph.transcript.isEmpty {
            paragraphTexts.insert(paragraph.transcript)
            textParts.append(paragraph.transcript)
            markdownParts.append(paragraph.transcript)
            blocks.append(OCRTextBlock(text: paragraph.transcript))
        }
        if container.paragraphs.isEmpty, !container.text.transcript.isEmpty {
            textParts.append(container.text.transcript)
            markdownParts.append(container.text.transcript)
            blocks.append(OCRTextBlock(text: container.text.transcript))
        }
        for list in container.lists {
            let lines = list.items.map { "- \($0.itemString)" }
            let joined = lines.joined(separator: "\n")
            guard !joined.isEmpty else { continue }
            // List item prose may already appear in the transcript; keep the
            // structured Markdown line without re-adding a plain-text copy.
            if !paragraphTexts.contains(joined) { textParts.append(joined) }
            markdownParts.append(joined)
        }
        for table in container.tables {
            var cells: [OCRTableCell] = []
            var grid: [[String]] = []
            var spanned = false
            for row in table.rows {
                var line: [String] = []
                for cell in row {
                    let transcript = cell.content.text.transcript
                    line.append(transcript)
                    cells.append(OCRTableCell(
                        text: transcript,
                        rowRange: cell.rowRange.lowerBound..<cell.rowRange.upperBound + 1,
                        columnRange: cell.columnRange.lowerBound..<cell.columnRange.upperBound + 1
                    ))
                    if cell.rowRange.count > 1 || cell.columnRange.count > 1 { spanned = true }
                }
                grid.append(line)
            }
            guard !cells.isEmpty else { continue }
            tables.append(OCRTable(cells: cells))
            let flat = cells.map(\.text).joined(separator: " ")
            if !flat.isEmpty, !paragraphTexts.contains(flat) { textParts.append(flat) }
            markdownParts.append(markdownTable(grid: grid, spanned: spanned))
        }
        return true
    }

    private func markdownTable(grid: [[String]], spanned: Bool) -> String {
        guard let width = grid.map(\.count).max(), width > 0 else { return "" }
        if spanned {
            // Spans don't fit Markdown; keep an escaped HTML table so no cell is duplicated.
            var html = "<table>"
            for row in grid {
                html += "<tr>"
                for i in 0..<width {
                    let cell = i < row.count ? row[i] : ""
                    html += "<td>\(escapeHTML(cell))</td>"
                }
                html += "</tr>"
            }
            return html + "</table>"
        }
        let header = (0..<width).map { "col\($0 + 1)" }
        var lines = [
            "| " + header.joined(separator: " | ") + " |",
            "| " + header.map({ _ in "---" }).joined(separator: " | ") + " |",
        ]
        for row in grid {
            var padded = row
            while padded.count < width { padded.append("") }
            lines.append("| " + padded.map(escapePipe).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    private func escapePipe(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeHeading(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }
}
