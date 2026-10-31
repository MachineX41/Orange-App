import AppKit
import Foundation
import OrangeKit

/// Executes the OCR queue owned by `AppRuntime.ocrWorkspace`.
/// Exports use the edited buffers and never touch originals.
@MainActor
final class OCRRunner {
    private let runtime: AppRuntime

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    private var model: OCRWorkspaceModel { runtime.ocrWorkspace }

    func run() {
        guard !model.isRunning, !model.sources.isEmpty else { return }
        let options = model.options
        let sources = model.sources
        let runID = model.runID + 1
        let task = runtime.run(
            "OCR", symbol: "text.viewfinder",
            detail: optionsLabel(options),
            successMessage: "OCR complete",
            cancellable: true
        ) { [weak self] progress in
            guard let self else { return [] }
            do {
                try await self.execute(runID: runID, options: options, sources: sources, progress: progress)
            } catch is CancellationError {
                await MainActor.run { [weak self] in self?.model.cancelRun() }
                throw CancellationError()
            } catch let error as OrangeError where error == .cancelled {
                await MainActor.run { [weak self] in self?.model.cancelRun() }
                throw error
            } catch {
                await MainActor.run { [weak self] in self?.model.failRun((error as? OrangeError)?.message ?? error.localizedDescription) }
                throw error
            }
            return []
        }
        model.beginRun(options: options, task: task, runID: runID)
    }

    func cancel() {
        model.task?.cancel()
        model.cancelRun()
    }

    private func optionsLabel(_ options: OCROptions) -> String {
        let name = OCRModelCatalog.entry(for: options.modelID)?.displayName ?? options.modelID.rawValue
        return "\(name) · \(options.mode.rawValue)"
    }

    private func execute(runID: Int, options: OCROptions, sources: [OCRWorkspaceModel.SourceFile], progress: @escaping ProgressHandler) async throws {
        let total = sources.reduce(0) { $0 + $1.pageCount }
        var done = 0
        await setPhase(.loadingModel, runID: runID)
        for source in sources {
            try Task.checkCancellation()
            let result = try await OCRService.shared.recognize(
                url: source.url, options: options,
                onPage: { [weak self] page in
                    guard let self else { return }
                    Task { @MainActor [weak self] in
                        self?.applyPage(page, runID: runID)
                    }
                },
                progress: { value in
                    let overall = total > 0 ? (Double(done) + value) / Double(total) : value
                    progress(overall)
                }
            )
            for page in result.pages {
                await applyPage(page, runID: runID)
                done += 1
                await setPhase(.recognizing(current: done, total: total), runID: runID)
            }
        }
        await MainActor.run { [weak self] in
            guard let self, model.runID == runID else { return }
            model.finishRun()
        }
    }

    private func setPhase(_ phase: OCRWorkspaceModel.Phase, runID: Int) async {
        await MainActor.run { [weak self] in
            guard let self, model.runID == runID else { return }
            model.phase = phase
        }
    }

    private func applyPage(_ page: OCRPageResult, runID: Int) {
        guard model.runID == runID else { return }
        guard let index = model.pages.firstIndex(where: {
            $0.sourceURL.standardizedFileURL == page.sourceURL.standardizedFileURL && $0.pageIndex == page.pageIndex
        }) else { return }
        model.pages[index].text = page.content.text
        model.pages[index].editedText = page.content.text
        model.pages[index].markdown = page.content.markdown
        model.pages[index].editedMarkdown = page.content.markdown ?? ""
        model.pages[index].embeddedTextUsed = page.embeddedTextUsed
        model.pages[index].actualCompute = page.content.actualCompute
        model.pages[index].stale = false
        model.activeComputeLabel = computeLabel(page.content.actualCompute)
    }

    private func computeLabel(_ compute: OCRActualCompute) -> String {
        switch compute {
        case .appleManaged: "System managed"
        case .metal: "Metal"
        case .cpu: "CPU"
        case .metalTextCPUProjector: "Metal + CPU"
        }
    }

    // MARK: - Export (edited buffers, originals untouched)

    func exportText(page: OCRWorkspaceModel.PageState) throws -> URL {
        let text = page.editedText.isEmpty ? page.text : page.editedText
        return try write(text: text, extension: "txt", source: page.sourceURL)
    }

    func exportAllText() throws -> URL {
        let text = model.pages.map { $0.editedText.isEmpty ? $0.text : $0.editedText }.joined(separator: "\n\n")
        let base = model.sources.first?.url ?? URL(fileURLWithPath: "OCR.txt")
        return try write(text: text, extension: "txt", source: base)
    }

    func exportMarkdown(page: OCRWorkspaceModel.PageState) throws -> URL {
        let markdown = page.editedMarkdown.isEmpty ? (page.markdown ?? page.text) : page.editedMarkdown
        return try write(text: markdown, extension: "md", source: page.sourceURL)
    }

    func exportAllMarkdown() throws -> URL {
        let markdown = model.pages.map {
            $0.editedMarkdown.isEmpty ? ($0.markdown ?? $0.text) : $0.editedMarkdown
        }.joined(separator: "\n\n---\n\n")
        let base = model.sources.first?.url ?? URL(fileURLWithPath: "OCR.md")
        return try write(text: markdown, extension: "md", source: base)
    }

    private func write(text: String, extension ext: String, source: URL) throws -> URL {
        let destination = UniqueDestination.url(
            in: OutputLocation.directory(beside: source),
            baseName: OutputLocation.baseName(source),
            extension: ext
        )
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw OrangeError.writeFailed(destination.lastPathComponent)
        }
        return destination
    }
}
