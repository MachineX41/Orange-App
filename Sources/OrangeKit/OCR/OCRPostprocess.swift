import Foundation

/// Post-processing for document-mode Markdown export (Marker/MarkItDown recipe).
/// Pure Swift, no model calls.
public enum OCRPostprocess {
    /// Removes running headers/footers: a first or last non-empty line that
    /// repeats verbatim on 3+ pages (journal headers, page numbers, DOIs).
    /// Single-page documents are returned unchanged.
    public static func stripRunningHeaders(_ pages: [String]) -> [String] {
        guard pages.count >= 3 else { return pages }
        var firstCounts: [String: Int] = [:]
        var lastCounts: [String: Int] = [:]
        let heads = pages.map { headLine($0) }
        let tails = pages.map { tailLine($0) }
        for h in heads.compactMap({ $0 }) { firstCounts[h, default: 0] += 1 }
        for tl in tails.compactMap({ $0 }) { lastCounts[tl, default: 0] += 1 }
        let badHeads = Set(firstCounts.filter { $0.value >= 3 }.keys)
        let badTails = Set(lastCounts.filter { $0.value >= 3 }.keys)
        guard !badHeads.isEmpty || !badTails.isEmpty else { return pages }
        return pages.map { stripPage($0, badHeads: badHeads, badTails: badTails) }
    }

    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
    }

    private static func headLine(_ text: String) -> String? {
        lines(text).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func tailLine(_ text: String) -> String? {
        lines(text).reversed().first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Rewrites hallucinated image URLs to plain figure placeholders.
    /// Models emit `![](https://...)`, `![](image-url)`, `![](#)` even when told
    /// not to; the URL is always invented since the model has no file access.
    /// `![alt](real-local-path.png)` is kept (produced by image extraction).
    public static func sanitizeFigureURLs(_ text: String) -> String {
        var result = text
        // ![](http...) or ![](https...) with empty/short alt -> figure placeholder
        result = result.replacingOccurrences(
            of: #"!\[([^\]]{0,80})\]\(https?://[^)]*\)"#,
            with: "![Figure: $1]",
            options: .regularExpression
        )
        // ![](image-url), ![](#), ![](image.png) generics -> placeholder
        result = result.replacingOccurrences(
            of: #"!\[([^\]]{0,80})\]\((?:image-url|#|image\.png)\)"#,
            with: "![Figure: $1]",
            options: .regularExpression
        )
        // Empty alt with invented URL: ![](https://...) -> ![Figure]
        result = result.replacingOccurrences(
            of: #"!\[\]\(https?://[^)]*\)"#,
            with: "![Figure]",
            options: .regularExpression
        )
        return result
    }

    private static func stripPage(_ text: String, badHeads: Set<String>, badTails: Set<String>) -> String {
        var result = lines(text)
        // Strip at most one head and one tail line per page.
        if let first = result.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           badHeads.contains(result[first].trimmingCharacters(in: .whitespaces))
        {
            result.remove(at: first)
        }
        if let last = result.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           badTails.contains(result[last].trimmingCharacters(in: .whitespaces))
        {
            result.remove(at: last)
        }
        return result.joined(separator: "\n")
    }
}
