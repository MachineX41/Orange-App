import AppKit
import OrangeKit
import SwiftUI

@MainActor
@Observable
final class AppRuntime {
    static let shared = AppRuntime()

    var section: Section = .home
    var selection: [FileRef] = []
    var jobs: [JobRecord] = []
    var shelf: [FileRef] = []
    var localWheel: WheelSession?
    var globalWheel: WheelSession?
    var globalHighlight: Int?
    var localHighlight: Int?
    var sheet: SheetRoute?
    var importerPresented = false
    var alertText: String?
    var globalMonitorAvailable = true
    var pendingTool: ToolID?

    var appearance: AppearanceChoice
    var revealWhenDone: Bool
    var soundOnDone: Bool
    var hapticOnWheel: Bool
    var jpegQuality: Double

    var isWorking: Bool { jobs.contains { $0.state == .running } }

    var recentOutputs: [FileRef] {
        jobs.filter { $0.state == .success }
            .flatMap(\.outputPaths)
            .compactMap { FileRef.load(URL(fileURLWithPath: $0)) }
            .prefix(8)
            .map { $0 }
    }

    private let defaults = UserDefaults.standard
    private let store = LibraryStore()

    private enum Keys {
        static let appearance = "appearance"
        static let reveal = "revealWhenDone"
        static let sound = "soundOnDone"
        static let haptic = "hapticOnWheel"
        static let quality = "jpegQuality"
    }

    private init() {
        appearance = AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: Keys.appearance) ?? "") ?? .system
        if UserDefaults.standard.object(forKey: Keys.reveal) == nil {
            revealWhenDone = true
            soundOnDone = true
            hapticOnWheel = true
            jpegQuality = 0.9
        } else {
            revealWhenDone = UserDefaults.standard.bool(forKey: Keys.reveal)
            soundOnDone = UserDefaults.standard.object(forKey: Keys.sound) as? Bool ?? true
            hapticOnWheel = UserDefaults.standard.object(forKey: Keys.haptic) as? Bool ?? true
            jpegQuality = UserDefaults.standard.object(forKey: Keys.quality) as? Double ?? 0.9
        }
        let snapshot = store.load()
        jobs = snapshot.jobs.map { job in
            guard job.state == .running else { return job }
            var copy = job
            copy.state = .failure
            copy.detail = Copy.interrupted
            return copy
        }
        shelf = snapshot.shelf.compactMap { FileRef.load(URL(fileURLWithPath: $0)) }
        if jobs != snapshot.jobs || shelf.map(\.path) != snapshot.shelf {
            persist()
        }
    }

    func noteSettingsChanged() {
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
        defaults.set(revealWhenDone, forKey: Keys.reveal)
        defaults.set(soundOnDone, forKey: Keys.sound)
        defaults.set(hapticOnWheel, forKey: Keys.haptic)
        defaults.set(jpegQuality, forKey: Keys.quality)
    }

    func importURLs(_ urls: [URL]) {
        let files = urls.compactMap { FileRef.load($0) }
        guard !files.isEmpty else {
            alertText = OrangeError.empty.localizedDescription
            return
        }
        selection = files
        section = .home
        if let tool = pendingTool {
            pendingTool = nil
            perform(tool, files: files)
        }
    }

    func useSample() {
        do {
            let url = try SampleMaker.write()
            guard let file = FileRef.load(url) else { return }
            selection = [file]
            section = .home
        } catch {
            alertText = error.localizedDescription
        }
    }

    func removeFromSelection(_ file: FileRef) {
        selection.removeAll { $0 == file }
    }

    func removeFromShelf(_ file: FileRef) {
        shelf.removeAll { $0 == file }
        persist()
    }

    func request(_ tool: ToolID) {
        if selection.isEmpty {
            pendingTool = tool
            importerPresented = true
            return
        }
        perform(tool, files: selection)
    }

    func presentLocalWheel(_ mode: WheelMode) {
        let files = selection
        guard !files.isEmpty else {
            alertText = OrangeError.empty.localizedDescription
            return
        }
        let choices = makeChoices(mode, files: files)
        guard !choices.isEmpty else {
            alertText = Copy.noSharedFormat
            return
        }
        localHighlight = 0
        localWheel = WheelSession(mode: mode, files: files, choices: choices)
    }

    func nudgeLocalHighlight(_ delta: Int) {
        guard let session = localWheel, !session.choices.isEmpty else { return }
        let current = localHighlight ?? 0
        let count = session.choices.count
        localHighlight = (current + delta + count) % count
    }

    func commitLocalHighlight() {
        guard let session = localWheel, let index = localHighlight, session.choices.indices.contains(index) else { return }
        commit(choice: session.choices[index], files: session.files)
    }

    func updateGlobalWheel(files: [URL], mode: WheelMode, highlight: Int?) {
        let refs = files.compactMap { FileRef.load($0) }
        guard !refs.isEmpty else { return }
        let choices = makeChoices(mode, files: refs)
        guard !choices.isEmpty else { return }
        let session = WheelSession(mode: mode, files: refs, choices: choices)
        if globalWheel?.signature != session.signature {
            globalWheel = session
        }
        if hapticOnWheel, highlight != globalHighlight, highlight != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        globalHighlight = highlight
    }

    func clearGlobalWheel() {
        globalWheel = nil
        globalHighlight = nil
    }

    func commit(choice: WheelChoice, files: [FileRef]) {
        localWheel = nil
        globalWheel = nil
        globalHighlight = nil
        switch choice.payload {
        case .convert(let target):
            convert(files, to: target)
        case .tool(let tool):
            perform(tool, files: files)
        case .action(let action):
            perform(action, files: files)
        }
    }

    func perform(_ tool: ToolID, files: [FileRef]) {
        switch tool {
        case .convert:
            selection = files
            presentLocalWheel(.convert)
        case .compress:
            let images = files.filter { $0.kind == .image }
            guard !images.isEmpty else { alertText = Copy.needImages; return }
            sheet = .compress(images)
        case .resize:
            guard let file = singleImage(files) else { return }
            sheet = .resize(file)
        case .crop:
            guard let file = singleImage(files) else { return }
            sheet = .crop(file)
        case .rotate:
            guard let file = singleImage(files) else { return }
            sheet = .rotate(file)
        case .stripMetadata:
            let images = files.filter { $0.kind == .image }
            guard !images.isEmpty else { alertText = Copy.needImages; return }
            stripMetadata(images)
        case .imagesToPDF:
            let images = files.filter { $0.kind == .image }
            guard !images.isEmpty else { alertText = Copy.needImages; return }
            makePDF(from: images)
        case .mergePDF:
            let pdfs = files.filter { $0.kind == .pdf }
            guard pdfs.count >= 2 else { alertText = Copy.needTwoPDFs; return }
            merge(pdfs)
        case .splitPDF:
            guard files.count == 1, let file = files.first, file.kind == .pdf else {
                alertText = Copy.needOnePDF
                return
            }
            sheet = .split(file)
        case .archive:
            if files.count == 1, let file = files.first, file.kind == .archive {
                unzip(file)
            } else {
                zip(files)
            }
        }
    }

    func perform(_ action: ActionID, files: [FileRef]) {
        switch action {
        case .float:
            for file in files where !shelf.contains(file) {
                shelf.insert(file, at: 0)
            }
            persist()
        case .copy:
            let board = NSPasteboard.general
            board.clearContents()
            board.writeObjects(files.map { $0.url as NSURL })
        case .move:
            move(files)
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(files.map(\.path).joined(separator: "\n"), forType: .string)
        case .duplicate:
            duplicate(files)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url))
        case .airDrop:
            airDrop(files)
        case .zip:
            zip(files)
        }
    }

    func exportImage(_ file: FileRef, operation: ImageOperation, format: ConvertTarget, quality: Double) {
        Task {
            let id = startJob(title: file.name, detail: Copy.converting(format))
            do {
                let output = try await transcode(file, operation: operation, format: format, quality: quality)
                finish(id: id, outputs: [output], detail: output.lastPathComponent)
                celebrate([output])
            } catch {
                fail(id: id, message: error.localizedDescription)
            }
        }
    }

    func exportTurn(_ file: FileRef, degrees: Int, flipped: Bool, format: ConvertTarget) {
        Task {
            let id = startJob(title: file.name, detail: Copy.toolTitle(.rotate))
            do {
                let directory = OutputLocation.directory(beside: file.url)
                let quality = jpegQuality
                let sourceURL = file.url
                let output = try await Task.detached {
                    let transcoder = ImageTranscoder()
                    var source = sourceURL
                    var scratch: URL?
                    if flipped {
                        let flippedURL = try transcoder.convert(
                            ImageRequest(
                                source: source,
                                operation: .flipHorizontal,
                                format: .png,
                                quality: 1,
                                directory: FileManager.default.temporaryDirectory
                            )
                        )
                        scratch = flippedURL
                        source = flippedURL
                    }
                    let operation: ImageOperation = degrees == 0 ? .original : .rotateClockwise(degrees)
                    let result = try transcoder.convert(
                        ImageRequest(source: source, operation: operation, format: format, quality: quality, directory: directory)
                    )
                    if let scratch {
                        try? FileManager.default.removeItem(at: scratch)
                    }
                    return result
                }.value
                finish(id: id, outputs: [output], detail: output.lastPathComponent)
                celebrate([output])
            } catch {
                fail(id: id, message: error.localizedDescription)
            }
        }
    }

    func exportCompressed(_ files: [FileRef], quality: Double) {
        Task {
            var outputs: [URL] = []
            for file in files where file.kind == .image {
                let id = startJob(title: file.name, detail: Copy.toolTitle(.compress))
                do {
                    let output = try await transcode(file, operation: .original, format: .jpeg, quality: quality)
                    finish(id: id, outputs: [output], detail: output.lastPathComponent)
                    outputs.append(output)
                } catch {
                    fail(id: id, message: error.localizedDescription)
                }
            }
            celebrate(outputs)
        }
    }

    func splitPDF(_ file: FileRef, selection: String) {
        Task {
            let id = startJob(title: file.name, detail: Copy.toolTitle(.splitPDF))
            do {
                let directory = OutputLocation.directory(beside: file.url)
                let text = selection
                let source = file.url
                let outputs = try await Task.detached {
                    try PDFToolkit.split(url: source, selection: text, into: directory)
                }.value
                finish(id: id, outputs: outputs, detail: Copy.count(outputs.count))
                celebrate(outputs)
            } catch {
                fail(id: id, message: error.localizedDescription)
            }
        }
    }

    private func convert(_ files: [FileRef], to target: ConvertTarget) {
        Task {
            var outputs: [URL] = []
            for file in files {
                let id = startJob(title: file.name, detail: Copy.converting(target))
                do {
                    let output = try await runConvert(file, target: target)
                    finish(id: id, outputs: [output], detail: output.lastPathComponent)
                    outputs.append(output)
                } catch {
                    fail(id: id, message: error.localizedDescription)
                }
            }
            celebrate(outputs)
        }
    }

    private func stripMetadata(_ files: [FileRef]) {
        Task {
            var outputs: [URL] = []
            for file in files {
                let format = rasterFormat(for: file)
                let id = startJob(title: file.name, detail: Copy.toolTitle(.stripMetadata))
                do {
                    let output = try await transcode(file, operation: .original, format: format, quality: jpegQuality)
                    finish(id: id, outputs: [output], detail: output.lastPathComponent)
                    outputs.append(output)
                } catch {
                    fail(id: id, message: error.localizedDescription)
                }
            }
            celebrate(outputs)
        }
    }

    private func makePDF(from files: [FileRef]) {
        Task {
            let id = startJob(title: Copy.toolTitle(.imagesToPDF), detail: Copy.count(files.count))
            do {
                let sources = files.map(\.url)
                let directory = OutputLocation.directory(beside: files[0].url)
                let quality = jpegQuality
                let output = try await Task.detached {
                    try PDFToolkit.imagesToPDF(sources: sources, quality: quality, into: directory)
                }.value
                finish(id: id, outputs: [output], detail: output.lastPathComponent)
                celebrate([output])
            } catch {
                fail(id: id, message: error.localizedDescription)
            }
        }
    }

    private func merge(_ files: [FileRef]) {
        Task {
            let id = startJob(title: Copy.toolTitle(.mergePDF), detail: Copy.count(files.count))
            do {
                let sources = files.map(\.url)
                let directory = OutputLocation.directory(beside: files[0].url)
                let output = try await Task.detached {
                    try PDFToolkit.merge(urls: sources, into: directory)
                }.value
                finish(id: id, outputs: [output], detail: output.lastPathComponent)
                celebrate([output])
            } catch {
                fail(id: id, message: error.localizedDescription)
            }
        }
    }

    private func zip(_ files: [FileRef]) {
        let sources = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !sources.isEmpty else { return }
        Task {
            let id = startJob(title: Copy.actionTitle(.zip), detail: Copy.count(sources.count))
            do {
                let urls = sources.map(\.url)
                let directory = OutputLocation.directory(beside: sources[0].url)
                let output = try await Task.detached {
                    try ArchiveToolkit.zip(urls: urls, into: directory)
                }.value
                finish(id: id, outputs: [output], detail: output.lastPathComponent)
                celebrate([output])
            } catch {
                fail(id: id, message: error.localizedDescription)
            }
        }
    }

    private func unzip(_ file: FileRef) {
        Task {
            let id = startJob(title: file.name, detail: Copy.toolTitle(.archive))
            do {
                let source = file.url
                let directory = OutputLocation.directory(beside: source)
                let output = try await Task.detached {
                    try ArchiveToolkit.unzip(archive: source, into: directory)
                }.value
                finish(id: id, outputs: [output], detail: output.lastPathComponent)
                celebrate([output])
            } catch {
                fail(id: id, message: error.localizedDescription)
            }
        }
    }

    private func duplicate(_ files: [FileRef]) {
        Task {
            var outputs: [URL] = []
            for file in files {
                let id = startJob(title: file.name, detail: Copy.actionTitle(.duplicate))
                do {
                    let directory = OutputLocation.directory(beside: file.url)
                    let destination = UniqueDestination.url(
                        in: directory,
                        baseName: file.url.deletingPathExtension().lastPathComponent,
                        extension: file.url.pathExtension
                    )
                    try FileManager.default.copyItem(at: file.url, to: destination)
                    finish(id: id, outputs: [destination], detail: destination.lastPathComponent)
                    outputs.append(destination)
                } catch {
                    fail(id: id, message: error.localizedDescription)
                }
            }
            celebrate(outputs)
        }
    }

    private func move(_ files: [FileRef]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = Copy.chooseFolder
        panel.message = Copy.moveTitle
        panel.begin { [files] response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in
                var outputs: [URL] = []
                for file in files {
                    let id = self.startJob(title: file.name, detail: Copy.actionTitle(.move))
                    do {
                        let destination = UniqueDestination.url(
                            in: folder,
                            baseName: file.url.deletingPathExtension().lastPathComponent,
                            extension: file.url.pathExtension
                        )
                        try FileManager.default.moveItem(at: file.url, to: destination)
                        self.finish(id: id, outputs: [destination], detail: destination.lastPathComponent)
                        outputs.append(destination)
                    } catch {
                        self.fail(id: id, message: error.localizedDescription)
                    }
                }
                self.selection.removeAll { selected in files.contains(selected) }
                self.celebrate(outputs)
            }
        }
    }

    private func airDrop(_ files: [FileRef]) {
        let urls = files.map(\.url)
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            alertText = Copy.airDropUnavailable
            return
        }
        service.perform(withItems: urls)
    }

    private func runConvert(_ file: FileRef, target: ConvertTarget) async throws -> URL {
        if target.isRaster {
            return try await transcode(file, operation: .original, format: target, quality: jpegQuality)
        }
        let directory = OutputLocation.directory(beside: file.url)
        return try await MediaTranscoder().export(source: file.url, target: target, directory: directory)
    }

    private func transcode(
        _ file: FileRef,
        operation: ImageOperation,
        format: ConvertTarget,
        quality: Double
    ) async throws -> URL {
        let request = ImageRequest(
            source: file.url,
            operation: operation,
            format: format,
            quality: quality,
            directory: OutputLocation.directory(beside: file.url)
        )
        return try await Task.detached {
            try ImageTranscoder().convert(request)
        }.value
    }

    private func rasterFormat(for file: FileRef) -> ConvertTarget {
        switch file.url.pathExtension.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "png": .png
        case "webp": .webp
        case "heic", "heif": .heic
        case "tif", "tiff": .tiff
        case "bmp": .bmp
        case "gif": .gif
        default: .jpeg
        }
    }

    private func singleImage(_ files: [FileRef]) -> FileRef? {
        guard files.count == 1, let file = files.first, file.kind == .image else {
            alertText = Copy.needOneImage
            return nil
        }
        return file
    }

    @discardableResult
    private func startJob(title: String, detail: String) -> UUID {
        let job = JobRecord(
            id: UUID(),
            title: title,
            detail: detail,
            createdAt: .now,
            state: .running,
            outputPaths: []
        )
        jobs.insert(job, at: 0)
        if jobs.count > 200 { jobs.removeLast(jobs.count - 200) }
        persist()
        return job.id
    }

    private func finish(id: UUID, outputs: [URL], detail: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .success
        jobs[index].detail = detail
        jobs[index].outputPaths = outputs.map(\.path)
        persist()
    }

    private func fail(id: UUID, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .failure
        jobs[index].detail = message
        persist()
    }

    private func celebrate(_ outputs: [URL]) {
        guard !outputs.isEmpty else { return }
        if revealWhenDone {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
        if soundOnDone {
            NSSound(named: "Glass")?.play()
        }
    }

    private func makeChoices(_ mode: WheelMode, files: [FileRef]) -> [WheelChoice] {
        switch mode {
        case .convert:
            return Catalog.commonConvertTargets(for: files.map(\.kind)).map { target in
                WheelChoice(
                    id: target.rawValue,
                    title: Copy.targetTitle(target),
                    symbol: Copy.symbol(for: target),
                    payload: .convert(target)
                )
            }
        case .tools:
            return Catalog.commonTools(for: files.map(\.kind)).map { tool in
                WheelChoice(
                    id: tool.rawValue,
                    title: Copy.toolTitle(tool),
                    symbol: Copy.symbol(for: tool),
                    payload: .tool(tool)
                )
            }
        case .actions:
            return ActionID.allCases.map { action in
                WheelChoice(
                    id: action.rawValue,
                    title: Copy.actionTitle(action),
                    symbol: Copy.symbol(for: action),
                    payload: .action(action)
                )
            }
        }
    }

    private func persist() {
        store.save(LibrarySnapshot(jobs: jobs, shelf: shelf.map(\.path)))
    }
}
