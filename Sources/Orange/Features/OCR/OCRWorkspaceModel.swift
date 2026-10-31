import CoreGraphics
import Foundation
import Observation
import OrangeKit

/// Persistent OCR session owned by AppRuntime — survives tab switches because
/// the view layer is recreated on section change but this model is not.
@MainActor
@Observable
final class OCRWorkspaceModel {
    enum Phase: Equatable {
        case idle
        case preparing
        case loadingModel
        case recognizing(current: Int, total: Int)
        case done
        case cancelled
        case failed(String)
    }

    struct SourceFile: Identifiable, Equatable {
        var url: URL
        var id: String { url.standardizedFileURL.path }
        var name: String { url.lastPathComponent }
        var pageCount: Int
    }

    struct PageState: Identifiable, Equatable {
        var sourceURL: URL
        var pageIndex: Int
        var id: String { "\(sourceURL.standardizedFileURL.path)#\(pageIndex)" }
        /// 160px cached thumbnail, max 6 retained app-wide.
        var thumbnail: CGImage?
        var preview: CGImage?
        var text: String = ""
        var editedText: String = ""
        var editedMarkdown: String = ""
        var markdown: String?
        var embeddedTextUsed = false
        var actualCompute: OCRActualCompute = .appleManaged
        var stale = false
    }

    var sources: [SourceFile] = []
    var pages: [PageState] = []
    var selectedPageID: String?
    var options = OCROptions.appleDefault
    var showMarkdown = false
    var phase: Phase = .idle
    var activeModelName: String = "Apple"
    var activeComputeLabel: String = "System managed"
    var errorMessage: String?
    var runID = 0
    var task: Task<[URL], Never>?

    var isRunning: Bool { task != nil }

    func beginRun(options: OCROptions, task: Task<[URL], Never>, runID: Int? = nil) {
        self.runID = runID ?? (self.runID + 1)
        self.task = task
        self.phase = .preparing
        self.errorMessage = nil
        var snapshot = options
        // Clamp mode to what the selected model supports, defaulting to text.
        if let entry = OCRModelCatalog.entry(for: snapshot.modelID),
           !entry.modes.contains(snapshot.mode)
        {
            snapshot.mode = .text
        }
        self.options = snapshot
        self.activeModelName = OCRModelCatalog.entry(for: snapshot.modelID)?.displayName ?? snapshot.modelID.rawValue
        markOptionsChanged()
    }

    func finishRun() {
        task = nil
        if case .failed = phase { return }
        if case .cancelled = phase { return }
        phase = .done
    }

    func cancelRun() {
        task = nil
        phase = .cancelled
    }

    func failRun(_ message: String) {
        task = nil
        phase = .failed(message)
        errorMessage = message
    }

    var selectedPage: PageState? {
        get { pages.first { $0.id == selectedPageID } ?? pages.first }
        set {
            if let page = newValue { selectedPageID = page.id }
        }
    }

    func add(urls: [URL]) {
        guard !isRunning else { return }
        for url in urls {
            let standardized = url.standardizedFileURL
            guard [.image, .pdf].contains(Catalog.kind(for: standardized)) else { continue }
            guard !sources.contains(where: { $0.url.standardizedFileURL == standardized }) else { continue }
            let count = (try? OCRDocumentSource(url: standardized).pageCount()) ?? 1
            sources.append(SourceFile(url: standardized, pageCount: max(count, 1)))
        }
        rebuildEmptyPages()
    }

    func remove(source: SourceFile) {
        guard !isRunning else { return }
        sources.removeAll { $0.id == source.id }
        pages.removeAll { $0.sourceURL.standardizedFileURL == source.url.standardizedFileURL }
        if selectedPageID.map({ id in pages.contains(where: { $0.id == id }) }) != true {
            selectedPageID = pages.first?.id
        }
    }

    func clear() {
        guard !isRunning else { return }
        sources.removeAll()
        pages.removeAll()
        selectedPageID = nil
        phase = .idle
    }

    private func rebuildEmptyPages() {
        var next: [PageState] = []
        for source in sources {
            for index in 0..<source.pageCount {
                let id = "\(source.url.standardizedFileURL.path)#\(index)"
                if let existing = pages.first(where: { $0.id == id }) {
                    next.append(existing)
                } else {
                    next.append(PageState(sourceURL: source.url, pageIndex: index))
                }
            }
        }
        pages = next
        if selectedPageID == nil { selectedPageID = pages.first?.id }
    }

    func markOptionsChanged() {
        for index in pages.indices {
            if !pages[index].text.isEmpty { pages[index].stale = true }
        }
    }

    func updateText(_ text: String, for id: String) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].editedText = text
    }

    func updateMarkdown(_ markdown: String, for id: String) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].editedMarkdown = markdown
    }
}
