import CoreGraphics
import Foundation

/// VLM-backed engine that talks to the warm `OrangeOCRHelper` subprocess over
/// NDJSON IPC. Apple models never reach this path. Long-edge caps: 2048
/// balanced / 3072 high; small images are never upscaled. DeepSeek-2 always
/// keeps the projector on CPU (publisher Metal-precision note) — the UI
/// reports that split as `metalTextCPUProjector`, never plain `metal`.
///
/// Thread budget: `hw.perflevel0.physicalcpu` when present, else
/// `max(1, activeProcessorCount - 2)`, clamped to [1, 8].
public actor NativeOCREngine: OCREngine {
    public static func cpuThreads() -> Int {
        var size = MemoryLayout<Int32>.size
        var count: Int32 = 0
        if sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
            return min(max(Int(count), 1), 8)
        }
        let fallback = max(ProcessInfo.processInfo.activeProcessorCount - 2, 1)
        return min(fallback, 8)
    }

    public static func maxSide(for quality: OCRQuality) -> CGFloat {
        switch quality {
        case .balanced: 2048
        case .high: 3072
        }
    }

    private let helperURL: URL
    private let store: OCRModelStore

    private var process: Process?
    private var stdin: FileHandle?
    private var pending: [String: CheckedContinuation<OCRHelperIPC.Event, Error>] = [:]
    private var loadedKey: String?
    private var lastUse = Date.distantPast
    private var stderrTail = Data()
    private var stdoutBuffer = Data()
    private var terminated = false

    public init(helperURL: URL, store: OCRModelStore = OCRModelStore()) {
        self.helperURL = helperURL
        self.store = store
    }

    public func recognize(_ image: CGImage, options: OCROptions) async throws -> OCRPageContent {
        guard options.modelID != .appleVision else {
            throw OrangeError.unsupported("Apple uses the OS-managed engine, not the native helper.")
        }
        guard let entry = OCRModelCatalog.entry(for: options.modelID) else {
            throw OrangeError.unsupported(options.modelID.rawValue)
        }
        guard await store.status(for: entry) == .installed else {
            throw OrangeError.unreadable(entry.displayName)
        }
        if options.compute == .cpu, let reason = entry.cpuUnsupportedReason {
            throw OrangeError.unsupported(reason)
        }
        try Task.checkCancellation()
        let started = ContinuousClock.now
        let staged = try await stageImage(image, quality: options.quality)
        defer { try? FileManager.default.removeItem(at: staged.dir) }
        let actual = try await ensureLoaded(entry: entry, options: options)
        let event = try await sendRecognize(imagePath: staged.file.path, mode: options.mode)
        try Task.checkCancellation()
        guard let text = event.text else {
            throw OrangeError.toolFailed("Empty helper result")
        }
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let compute = OCRActualCompute(rawValue: event.actualCompute ?? "") ?? actual
        return OCRPageContent(
            text: text,
            markdown: event.markdown,
            actualCompute: compute,
            durationSeconds: event.durationSeconds ?? seconds,
            truncated: event.truncated ?? false
        )
    }

    /// Idle reaper hook: call from a timer; shuts the helper down after 60s idle.
    public func reapIfIdle(timeout: TimeInterval = 60) {
        guard Date().timeIntervalSince(lastUse) > timeout else { return }
        stopHelper()
    }

    /// Memory-pressure hook: drop the idle model immediately; a running job is
    /// cancelled with a visible warning instead.
    public func handleMemoryPressure() {
        if pending.isEmpty {
            stopHelper()
        } else {
            for (_, continuation) in pending {
                continuation.resume(throwing: OrangeError.toolFailed("Out of memory; idle model released."))
            }
            pending.removeAll()
            stopHelper()
        }
    }

    // MARK: - Process lifecycle

    private func ensureLoaded(entry: OCRModelEntry, options: OCROptions) async throws -> OCRActualCompute {
        let key = "\(entry.id.rawValue)|\(options.compute.rawValue)|\(options.quality.rawValue)"
        if loadedKey == key, process?.isRunning == true { return actualCompute(entry: entry, preference: options.compute) }
        stopHelper()
        try startHelper()
        let modelDir = await store.installedDirectory(for: entry.id, revision: entry.revision)
        let modelPath = modelDir.appendingPathComponent(entry.artifacts.first(where: { $0.role == "model" })?.filename ?? "").path
        let projectorPath = modelDir.appendingPathComponent(entry.artifacts.first(where: { $0.role == "projector" })?.filename ?? "").path
        let command = OCRHelperIPC.LoadCommand(
            modelID: entry.id,
            modelPath: modelPath,
            projectorPath: projectorPath,
            compute: options.compute,
            quality: options.quality,
            threads: Self.cpuThreads()
        )
        let event = try await send(command: command, requestID: command.requestID)
        guard event.type == "ready" else {
            throw helperError(from: event)
        }
        loadedKey = key
        lastUse = Date()
        return actualCompute(entry: entry, preference: options.compute)
    }

    private func actualCompute(entry: OCRModelEntry, preference: OCRComputePreference) -> OCRActualCompute {
        switch preference {
        case .cpu:
            return .cpu
        case .metal:
            return entry.projectorCPUOnly ? .metalTextCPUProjector : .metal
        case .automatic:
            return entry.projectorCPUOnly ? .metalTextCPUProjector : .metal
        }
    }

    private func startHelper() throws {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw OrangeError.unreadable(helperURL.lastPathComponent)
        }
        let process = Process()
        process.executableURL = helperURL
        process.arguments = []
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting
        self.terminated = false
        let stdout = stdoutPipe.fileHandleForReading
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.appendStdout(data) }
        }
        let stderr = stderrPipe.fileHandleForReading
        stderr.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.appendStderr(data) }
        }
    }

    /// Test-only: terminate the helper immediately.
    func shutdownForTests() {
        stopHelper()
    }

    private func stopHelper() {
        guard let process else {
            self.process = nil
            self.stdin = nil
            loadedKey = nil
            return
        }
        // Close stdin first: helper exits cleanly on EOF. Don't trust
        // Process.isRunning (stale KVO); verify via kill(pid, 0) instead.
        try? stdin?.close()
        self.stdin = nil
        let pid = process.processIdentifier
        let captured = process
        // Synchronous escalation: EOF already sent via stdin close.
        var alive = true
        for _ in 0..<20 {
            if kill(pid, 0) != 0 { alive = false; break }
            usleep(100_000)
        }
        if alive {
            captured.terminate()
            for _ in 0..<20 {
                if kill(pid, 0) != 0 { alive = false; break }
                usleep(100_000)
            }
        }
        if alive {
            kill(pid, SIGKILL)
        }
        self.process = nil
        loadedKey = nil
        // Wake every waiter: otherwise recognize() hangs forever on shutdown.
        for (_, continuation) in pending {
            continuation.resume(throwing: CancellationError())
        }
        pending.removeAll()
    }

    private func handleTermination() {
        terminated = true
        for (_, continuation) in pending {
            continuation.resume(throwing: OrangeError.toolFailed("OCR helper exited."))
        }
        pending.removeAll()
        process = nil
        stdin = nil
        loadedKey = nil
    }

    private func appendStdout(_ data: Data) {
        stdoutBuffer.append(data)
        if stdoutBuffer.count > 16 * 1024 * 1024 {
            // Single-line flood guard: fail the oldest waiter rather than growing.
            stdoutBuffer.removeAll()
            for (id, continuation) in pending {
                continuation.resume(throwing: OrangeError.toolFailed("Helper output overflow."))
                pending.removeValue(forKey: id)
                break
            }
            return
        }
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let event = try? JSONDecoder().decode(OCRHelperIPC.Event.self, from: Data(line)) else { continue }
            // Never let helper text leak into logs/telemetry as free content.
            if let id = event.requestID, let continuation = pending.removeValue(forKey: id) {
                lastUse = Date()
                continuation.resume(returning: event)
            }
        }
    }

    private func appendStderr(_ data: Data) {
        stderrTail.append(data)
        if stderrTail.count > 64 * 1024 {
            stderrTail.removeFirst(stderrTail.count - 64 * 1024)
        }
    }

    private func send(command: some Encodable & Sendable, requestID: String) async throws -> OCRHelperIPC.Event {
        guard let stdin else { throw OrangeError.toolFailed("OCR helper not running.") }
        let payload = try JSONEncoder().encode(command) + Data([0x0A])
        try stdin.write(contentsOf: payload)
        return try await withCheckedThrowingContinuation { continuation in
            pending[requestID] = continuation
        }
    }

    private func sendRecognize(imagePath: String, mode: OCRMode) async throws -> OCRHelperIPC.Event {
        let command = OCRHelperIPC.RecognizeCommand(imagePath: imagePath, mode: mode)
        let event = try await send(command: command, requestID: command.requestID)
        switch event.type {
        case "result":
            return event
        case "error":
            throw helperError(from: event)
        default:
            throw OrangeError.toolFailed("Unexpected helper event: \(event.type)")
        }
    }

    private func helperError(from event: OCRHelperIPC.Event) -> Error {
        let message = event.message ?? "Helper failed."
        switch event.code {
        case "metalUnavailable", "metalInitialization":
            return OrangeError.toolFailed(message)
        case "outOfMemory":
            return OrangeError.toolFailed(message)
        case "contextOverflow":
            return OrangeError.toolFailed(message)
        case "modelLoad":
            return OrangeError.toolFailed(message)
        default:
            return OrangeError.toolFailed(message)
        }
    }

    private func stageImage(_ image: CGImage, quality: OCRQuality) async throws -> (dir: URL, file: URL) {
        let maxSide = Self.maxSide(for: quality)
        let longest = max(image.width, image.height)
        let scaled: CGImage
        if CGFloat(longest) > maxSide {
            let scale = maxSide / CGFloat(longest)
            let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
            let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
            scaled = try ImageEngine.transform(image, .resize(width: width, height: height))
        } else {
            scaled = image
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orange-ocr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent("page.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let data = try ImageEngine.encode(scaled, as: .png, quality: 1.0)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return (dir, file)
    }
}
