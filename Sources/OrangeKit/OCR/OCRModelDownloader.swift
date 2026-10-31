import Foundation

/// Resumable one-artifact-at-a-time model downloader. `store` owns layout and
/// hash truth; this class owns only transport + resume state. One transfer at a
/// time across the whole app (guarded by `isActive`), no parallel multi-GB
/// downloads. Redirects stay on HTTPS; no credential/token prompts.
@MainActor
public final class OCRModelDownloader: NSObject {
    public enum Phase: Sendable, Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case paused(received: Int64, total: Int64)
        case verifying
        case installed
        case failed(message: String, canResume: Bool)
    }

    public private(set) var phase: Phase = .idle {
        didSet { onPhase?(phase) }
    }

    public var onPhase: ((Phase) -> Void)?
    public var isActive: Bool { task != nil }

    private let entry: OCRModelEntry
    private let store: OCRModelStore
    private let configuration: URLSessionConfiguration
    private let session: URLSession
    private let delegate: DownloadDelegate
    private var task: URLSessionDataTask?
    private var sink: PartSink?
    private var received: Int64 = 0

    private struct PartSink {
        var handle: FileHandle
        var partURL: URL
        var finalURL: URL
        var artifact: OCRModelArtifact
        var baseOffset: Int64
        var statusCode: Int = 0
        var contentRangeStart: Int64?
        var validator: Validator?
    }

    private struct Validator: Codable {
        var etag: String?
        var lastModified: String?
    }

    public init(entry: OCRModelEntry, store: OCRModelStore, configuration: URLSessionConfiguration = .default) {
        self.entry = entry
        self.store = store
        self.configuration = configuration
        let delegate = DownloadDelegate()
        self.delegate = delegate
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        super.init()
        delegate.owner = self
    }

    public func start() {
        guard task == nil else { return }
        guard !entry.artifacts.isEmpty else { return }
        phase = .downloading(received: receivedTotal(), total: entry.totalBytes)
        advance()
    }

    public func pause() {
        task?.cancel()
        task = nil
        closeSink()
        phase = .paused(received: receivedTotal(), total: entry.totalBytes)
    }

    public func cancel() {
        task?.cancel()
        task = nil
        closeSink()
        phase = .idle
    }

    // MARK: - Internals

    private func stagingDir() throws -> URL {
        // Store is an actor; layout is deterministic so mirror it synchronously.
        // Callers (MainActor) only need the path math, not actor state.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Orange/Models/.staging/\(entry.id.rawValue)/\(entry.revision)", isDirectory: true)
    }

    private func receivedTotal() -> Int64 {
        (try? completedBytes()) ?? 0
    }

    private func completedBytes() throws -> Int64 {
        let dir = try stagingDir()
        var total: Int64 = 0
        for artifact in entry.artifacts {
            let final = dir.appendingPathComponent(artifact.filename)
            if let size = try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == artifact.byteCount {
                total += Int64(size)
            }
        }
        return total
    }

    private func advance() {
        // Pick the first incomplete artifact.
        let dir = (try? stagingDir()) ?? URL(fileURLWithPath: "/dev/null")
        var done: Int64 = 0
        var next: OCRModelArtifact?
        for artifact in entry.artifacts {
            let final = dir.appendingPathComponent(artifact.filename)
            if let size = try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               Int64(size) == artifact.byteCount
            {
                done += Int64(size)
            } else if next == nil {
                next = artifact
            }
        }
        received = done
        guard let artifact = next else {
            verifyAndPromote()
            return
        }
        startArtifact(artifact, priorComplete: done)
    }

    private func startArtifact(_ artifact: OCRModelArtifact, priorComplete: Int64) {
        guard let dir = try? stagingDir() else {
            phase = .failed(message: OrangeError.writeFailed(artifact.filename).message, canResume: false)
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let final = dir.appendingPathComponent(artifact.filename)
        let part = dir.appendingPathComponent(artifact.filename + ".part")
        let partSize = (try? part.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        // Disk-space gate before the user's download: remaining + 256 MiB.
        let remaining = entry.totalBytes - priorComplete - min(partSize, artifact.byteCount)
        if let free = (try? FileManager.default.attributesOfFileSystem(forPath: dir.path)[.systemFreeSize] as? NSNumber)?.int64Value,
           free < remaining + 256 * 1024 * 1024
        {
            phase = .failed(message: "Not enough disk space.", canResume: true)
            return
        }

        var request = URLRequest(url: URL(string: "\(entry.downloadBaseURL)/\(artifact.filename)")!)
        if partSize > 0 {
            request.setValue("bytes=\(partSize)-", forHTTPHeaderField: "Range")
            if let validator = readValidator(for: artifact) {
                if let etag = validator.etag {
                    request.setValue(etag, forHTTPHeaderField: "If-Range")
                } else if let modified = validator.lastModified {
                    request.setValue(modified, forHTTPHeaderField: "If-Range")
                }
            }
        }
        FileManager.default.createFile(atPath: part.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: part) else {
            phase = .failed(message: OrangeError.writeFailed(artifact.filename).message, canResume: true)
            return
        }
        if partSize > 0 { _ = try? handle.seekToEnd() }
        sink = PartSink(handle: handle, partURL: part, finalURL: final, artifact: artifact, baseOffset: partSize)
        received = priorComplete
        phase = .downloading(received: received + partSize, total: entry.totalBytes)
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    private func verifyAndPromote() {
        phase = .verifying
        Task {
            do {
                for artifact in entry.artifacts {
                    let dir = try stagingDir()
                    try await store.verifyStagedFile(dir.appendingPathComponent(artifact.filename), artifact: artifact)
                }
                try await store.promoteStaging(entry)
                phase = .installed
            } catch {
                phase = .failed(message: (error as? OrangeError)?.message ?? error.localizedDescription, canResume: true)
            }
        }
    }

    // MARK: - Validators + status handling (testable without network)

    private func validatorURL(for artifact: OCRModelArtifact) -> URL? {
        (try? stagingDir())?.appendingPathComponent(artifact.filename + ".validator.json")
    }

    private func readValidator(for artifact: OCRModelArtifact) -> Validator? {
        guard let url = validatorURL(for: artifact),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Validator.self, from: data)
    }

    private func writeValidator(_ validator: Validator, for artifact: OCRModelArtifact) {
        guard let url = validatorURL(for: artifact),
              let data = try? JSONEncoder().encode(validator)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Pure status-code decisions so tests pin the resume contract exactly.
    enum ResumeDecision: Equatable {
        case appendFrom(Int64)
        case restart
        case complete
        case fatal(message: String)
    }

    static func resumeDecision(statusCode: Int, contentRange: String?, expectedSize: Int64?, partSize: Int64, contentLength: Int64?) -> ResumeDecision {
        switch statusCode {
        case 206:
            let start = parseRangeStart(contentRange)
            guard let start, start == partSize else {
                return .fatal(message: "Server resumed at the wrong offset.")
            }
            return .appendFrom(partSize)
        case 200:
            // Server ignored Range: restart from zero, never append.
            return .restart
        case 416:
            if let expectedSize, partSize == expectedSize { return .complete }
            return .fatal(message: "Download range invalid; restart the download.")
        case 404:
            return .fatal(message: "Model file not found.")
        case 429:
            return .fatal(message: "Rate limited; try again later.")
        case 500...599:
            return .fatal(message: "Server error; try again later.")
        default:
            return .fatal(message: "Download failed (HTTP \(statusCode)).")
        }
    }

    static func parseRangeStart(_ contentRange: String?) -> Int64? {
        // "bytes 123-456/789"
        guard let contentRange else { return nil }
        let parts = contentRange.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let range = parts[1].split(separator: "/").first ?? ""
        let start = range.split(separator: "-").first ?? ""
        return Int64(start)
    }

    private func closeSink() {
        if let sink {
            try? sink.handle.close()
            // Atomically rename completed parts to their final staged name.
            if let size = try? sink.partURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               Int64(size) == sink.artifact.byteCount
            {
                try? FileManager.default.removeItem(at: sink.finalURL)
                try? FileManager.default.moveItem(at: sink.partURL, to: sink.finalURL)
            }
        }
        sink = nil
    }
    fileprivate func handleResponse(statusCode: Int, headers: [AnyHashable: Any], expectedLength: Int64) -> Bool {
        guard let sink else { return false }
        let contentRange = (headers["Content-Range"] as? String) ?? (headers["content-range"] as? String)
        let decision = Self.resumeDecision(statusCode: statusCode, contentRange: contentRange, expectedSize: sink.artifact.byteCount, partSize: sink.baseOffset, contentLength: expectedLength > 0 ? expectedLength : nil)
        switch decision {
        case .appendFrom:
            if statusCode == 206 {
                if let etag = headers["Etag"] as? String ?? headers["ETag"] as? String {
                    writeValidator(Validator(etag: etag, lastModified: nil), for: sink.artifact)
                } else if let modified = headers["Last-Modified"] as? String {
                    writeValidator(Validator(etag: nil, lastModified: modified), for: sink.artifact)
                }
            }
            return true
        case .restart:
            // Server ignored Range: truncate and start over.
            try? sink.handle.truncate(atOffset: 0)
            var updated = sink
            updated.baseOffset = 0
            self.sink = updated
            received = receivedWithoutCurrent()
            return true
        case .complete:
            closeSink()
            task = nil
            advance()
            return false
        case .fatal(let message):
            task?.cancel()
            task = nil
            closeSink()
            phase = .failed(message: message, canResume: true)
            return false
        }
    }

    fileprivate func handleBytes(_ data: Data) {
        guard let handle = sink?.handle else { return }
        try? handle.write(contentsOf: data)
        received += Int64(data.count)
        phase = .downloading(received: received + (sink?.baseOffset ?? 0), total: entry.totalBytes)
    }

    fileprivate func handleCompletion(error: Error?) {
        guard sink != nil else { return }
        task = nil
        if let error = error as NSError?, error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            closeSink()
            phase = .paused(received: received + (sink?.baseOffset ?? 0), total: entry.totalBytes)
            return
        }
        if error != nil {
            closeSink()
            // Network drop keeps the part on disk; user resumes manually.
            phase = .paused(received: received + (sink?.baseOffset ?? 0), total: entry.totalBytes)
            return
        }
        let complete = (try? sink?.partURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == sink?.artifact.byteCount
        if complete {
            closeSink()
            advance()
        } else {
            closeSink()
            phase = .failed(message: "Download incomplete.", canResume: true)
        }
    }

    fileprivate func shouldRedirect(to url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https"
    }

    private func receivedWithoutCurrent() -> Int64 {
        var total: Int64 = 0
        guard let dir = try? stagingDir() else { return 0 }
        for artifact in entry.artifacts {
            if artifact.filename == sink?.artifact.filename { continue }
            let final = dir.appendingPathComponent(artifact.filename)
            if let size = try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == artifact.byteCount {
                total += Int64(size)
            }
        }
        return total
    }
}

final class DownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var owner: OCRModelDownloader?

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let owner, let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        Task { @MainActor in
            guard let owner = self.owner else {
                completionHandler(.cancel)
                return
            }
            let allow = owner.handleResponse(statusCode: http.statusCode, headers: http.allHeaderFields, expectedLength: response.expectedContentLength)
            completionHandler(allow ? .allow : .cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor [weak self] in self?.owner?.handleBytes(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in self?.owner?.handleCompletion(error: error) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let owner else {
            completionHandler(nil)
            return
        }
        Task { @MainActor in
            completionHandler(self.owner?.shouldRedirect(to: request.url) == true ? request : nil)
        }
        _ = owner
    }
}
