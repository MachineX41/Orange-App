import Foundation

public enum LinkDownloader {
    static let mediaExtensions: Set<String> = [
        "mp4", "mov", "m4v", "webm", "mkv", "mp3", "m4a", "wav", "aac", "flac", "ogg",
        "jpg", "jpeg", "png", "gif", "webp", "heic", "pdf", "zip"
    ]

    public static var downloaderPath: String? {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp",
                          NSHomeDirectory() + "/.local/bin/yt-dlp"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func normalize(_ raw: String) throws -> URL {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else {
            throw OrangeError.badLink
        }
        return url
    }

    public static func download(_ raw: String, audioOnly: Bool = false, into directory: URL, progress: ProgressHandler?) async throws -> [URL] {
        let url = try normalize(raw)
        if mediaExtensions.contains(url.pathExtension.lowercased()) {
            return [try await fetch(url, into: directory, progress: progress)]
        }
        if let tool = downloaderPath {
            return try await runDownloader(tool, url: url, audioOnly: audioOnly, into: directory, progress: progress)
        }
        if let media = try await discoverMedia(in: url) {
            return [try await fetch(media, into: directory, progress: progress, rejectPages: true)]
        }
        throw OrangeError.needsDownloader
    }

    // MARK: Direct

    static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static func fetch(_ url: URL, into directory: URL, progress: ProgressHandler?, rejectPages: Bool = false) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OrangeError.badLink
        }
        // A discovered "video" link that is really an embed page needs yt-dlp, not a saved .html file.
        if rejectPages, isPage(mimeType: http.mimeType) {
            throw OrangeError.needsDownloader
        }
        let expected = response.expectedContentLength
        let suggested = response.suggestedFilename ?? url.lastPathComponent
        var name = (suggested as NSString).deletingPathExtension
        if name.isEmpty { name = "Download" }
        var ext = (suggested as NSString).pathExtension
        if ext.isEmpty { ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension }
        let destination = UniqueDestination.url(in: directory, baseName: name, extension: ext)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var received: Int64 = 0
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 256 * 1024 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expected > 0 { progress?(min(0.99, Double(received) / Double(expected))) }
                    try Task.checkCancellation()
                }
            }
            try handle.write(contentsOf: buffer)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw Task.isCancelled ? OrangeError.cancelled : error
        }
        progress?(1)
        return destination
    }

    public static func isPage(mimeType: String?) -> Bool {
        guard let type = mimeType?.lowercased() else { return false }
        return type.hasPrefix("text/") || type.contains("html") || type.contains("xml") || type.contains("json")
    }

    /// Looks for Open Graph / Twitter video or image tags and `<video src>`.
    static func discoverMedia(in page: URL) async throws -> URL? {
        var request = URLRequest(url: page)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        return mediaLink(in: html, base: page)
    }

    public static func mediaLink(in html: String, base: URL) -> URL? {
        let keys = ["og:video:secure_url", "og:video:url", "og:video", "twitter:player:stream", "og:image:secure_url", "og:image"]
        for key in keys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let patterns = [
                "<meta[^>]+(?:property|name)=[\"']\(escaped)[\"'][^>]*content=[\"']([^\"']+)[\"']",
                "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"']\(escaped)[\"']"
            ]
            for pattern in patterns {
                if let value = firstMatch(pattern, in: html), let url = resolve(value, base: base) { return url }
            }
        }
        if let value = firstMatch("<(?:video|source)[^>]+src=[\"']([^\"']+)[\"']", in: html) {
            return resolve(value, base: base)
        }
        return nil
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).replacingOccurrences(of: "&amp;", with: "&")
    }

    static func resolve(_ value: String, base: URL) -> URL? {
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    // MARK: yt-dlp

    /// Turns yt-dlp's streamed output into a 0...1 fraction. Progress is often one line per update,
    /// but it also arrives as carriage-return rewrites, so every segment is parsed and the newest
    /// percentage in a chunk wins.
    public struct DownloadProgressReader: Sendable {
        private var pending = ""
        private var partFloor = 0.0
        private var previous = 0.0
        public private(set) var paths: [String] = []

        public init() {}

        public mutating func feed(_ chunk: String) -> [Double] {
            pending += Self.stripControls(chunk)
            var updates: [Double] = []
            while let breakIndex = pending.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                let line = String(pending[..<breakIndex])
                pending.removeSubrange(pending.startIndex...breakIndex)
                if let value = interpret(line) { updates.append(scale(value)) }
            }
            return updates
        }

        public mutating func finish() -> (progress: Double?, paths: [String]) {
            let rest = pending
            pending = ""
            return (interpret(rest).map { scale($0) }, paths)
        }

        private mutating func interpret(_ line: String) -> Double? {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasPrefix("ORANGEPROG:") {
                let raw = trimmed.dropFirst("ORANGEPROG:".count).trimmingCharacters(in: .whitespaces)
                guard let value = Double(raw) else { return nil }
                return min(1, max(0, value / 100))
            }
            if trimmed.hasPrefix("ORANGE:") {
                let path = String(trimmed.dropFirst("ORANGE:".count))
                if !path.isEmpty { paths.append(path) }
                return nil
            }
            guard trimmed.contains("[download]"),
                  let match = trimmed.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) else { return nil }
            let number = trimmed[match].dropLast()
            guard let value = Double(number) else { return nil }
            return min(1, max(0, value / 100))
        }

        /// Video and audio arrive as two downloads. Fold the second into the rest of the ring
        /// instead of snapping the indicator back to zero.
        private mutating func scale(_ raw: Double) -> Double {
            if raw + 0.05 < previous {
                partFloor = min(0.85, max(partFloor, previous))
            }
            previous = raw
            return min(0.99, partFloor + (1 - partFloor) * raw)
        }

        private static func stripControls(_ text: String) -> String {
            var output = ""
            var skipping = false
            for character in text {
                if character == "\u{1B}" {
                    skipping = true
                    continue
                }
                if skipping {
                    if character.isLetter { skipping = false }
                    continue
                }
                output.append(character)
            }
            return output
        }
    }

    final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var reader = DownloadProgressReader()
        private(set) var errors = ""
        let progress: ProgressHandler?

        init(progress: ProgressHandler?) { self.progress = progress }

        func consume(_ chunk: String) {
            let updates = ingest(chunk, isError: false)
            if let value = updates.last { progress?(value) }
        }

        func error(_ chunk: String) {
            let updates = ingest(chunk, isError: true)
            if let value = updates.last { progress?(value) }
        }

        func finish() -> [String] {
            lock.lock()
            let result = reader.finish()
            lock.unlock()
            if let value = result.progress { progress?(value) }
            return result.paths
        }

        private func ingest(_ chunk: String, isError: Bool) -> [Double] {
            lock.lock()
            if isError { errors += chunk }
            let updates = reader.feed(chunk)
            lock.unlock()
            return updates
        }
    }

    static func runDownloader(_ tool: String, url: URL, audioOnly: Bool, into directory: URL, progress: ProgressHandler?) async throws -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        var arguments = [
            "--no-playlist", "--newline", "--progress", "--no-mtime", "--restrict-filenames",
            "--progress-delta", "0.15",
            "--progress-template", "download:ORANGEPROG:%(progress._percent)s",
            "-P", directory.path,
            "-o", "%(title).120B.%(ext)s",
            "--print", "after_move:ORANGE:%(filepath)s"
        ]
        if audioOnly {
            arguments += ["-x", "--audio-format", "m4a"]
        } else {
            arguments += ["-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b", "--merge-output-format", "mp4"]
        }
        process.arguments = arguments + [url.absoluteString]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let collector = OutputCollector(progress: progress)
        let pipes = DispatchGroup()
        pipes.enter()
        pipes.enter()
        Self.stream(out.fileHandleForReading, group: pipes) { collector.consume($0) }
        Self.stream(err.fileHandleForReading, group: pipes) { collector.error($0) }
        try process.run()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    pipes.wait()
                    process.waitUntilExit()
                    continuation.resume()
                }
            }
        } onCancel: {
            process.terminate()
        }
        if Task.isCancelled { throw OrangeError.cancelled }
        let paths = collector.finish()
        guard process.terminationStatus == 0, !paths.isEmpty else {
            let message = collector.errors
                .components(separatedBy: "\n")
                .last { $0.contains("ERROR") } ?? collector.errors
            throw OrangeError.toolFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        progress?(1)
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// Reads a pipe until it closes, so each progress line is delivered as yt-dlp writes it.
    private static func stream(_ handle: FileHandle, group: DispatchGroup, receive: @escaping @Sendable (String) -> Void) {
        let gate = PipeGate()
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                gate.close {
                    handle.readabilityHandler = nil
                    group.leave()
                }
                return
            }
            receive(String(decoding: data, as: UTF8.self))
        }
    }

    private final class PipeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var closed = false

        func close(_ body: () -> Void) {
            lock.lock()
            let first = !closed
            closed = true
            lock.unlock()
            if first { body() }
        }
    }
}
