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
            return [try await fetch(media, into: directory, progress: progress)]
        }
        throw OrangeError.needsDownloader
    }

    // MARK: Direct

    static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static func fetch(_ url: URL, into directory: URL, progress: ProgressHandler?) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OrangeError.badLink
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
                if buffer.count >= 1 << 20 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expected > 0 { progress?(Double(received) / Double(expected)) }
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

    final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = ""
        private(set) var paths: [String] = []
        private(set) var errors = ""
        let progress: ProgressHandler?

        init(progress: ProgressHandler?) { self.progress = progress }

        func consume(_ chunk: String) {
            lock.lock()
            pending += chunk
            var lines = pending.components(separatedBy: "\n")
            pending = lines.removeLast()
            lock.unlock()
            for line in lines { handle(line) }
        }

        func error(_ chunk: String) {
            lock.lock()
            errors += chunk
            lock.unlock()
        }

        func finish() -> [String] {
            lock.lock()
            let rest = pending
            pending = ""
            lock.unlock()
            if !rest.isEmpty { handle(rest) }
            lock.lock()
            defer { lock.unlock() }
            return paths
        }

        private func handle(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("ORANGE:") {
                lock.lock()
                paths.append(String(trimmed.dropFirst(7)))
                lock.unlock()
            } else if trimmed.hasPrefix("[download]"),
                      let percent = trimmed.split(separator: " ").first(where: { $0.hasSuffix("%") }),
                      let value = Double(percent.dropLast()) {
                progress?(min(0.99, value / 100))
            }
        }
    }

    static func runDownloader(_ tool: String, url: URL, audioOnly: Bool, into directory: URL, progress: ProgressHandler?) async throws -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        var arguments = [
            "--no-playlist", "--newline", "--no-mtime", "--restrict-filenames",
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
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let collector = OutputCollector(progress: progress)
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.consume(String(decoding: data, as: UTF8.self)) }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.error(String(decoding: data, as: UTF8.self)) }
        }
        try process.run()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    continuation.resume()
                }
            }
        } onCancel: {
            process.terminate()
        }
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
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
}
