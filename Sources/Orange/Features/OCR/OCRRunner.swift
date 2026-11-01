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
        progress(0)
        for source in sources {
            try Task.checkCancellation()
            let result = try await OCRService.shared.recognize(
                url: source.url, options: options,
                onPage: { [weak self] page in
                    guard let self else { return }
                    Task { @MainActor [weak self] in
                        guard let self, model.runID == runID else { return }
                        self.applyPage(page, runID: runID)
                        // Page-granular progress: deterministic, monotonic.
                        // In-page engine progress is ignored (VLM has none).
                        self.pageCompleted(runID: runID, total: total, progress: progress)
                    }
                },
                progress: nil
            )
            // Pages already applied via onPage; result loop only guards missed callbacks.
            for page in result.pages where !isApplied(page) {
                applyPage(page, runID: runID)
                pageCompleted(runID: runID, total: total, progress: progress)
            }
            done = min(done + result.pages.count, total)
        }
        await MainActor.run { [weak self] in
            guard let self, model.runID == runID else { return }
            model.finishRun()
        }
    }

    /// Called on MainActor once per completed page.
    private func pageCompleted(runID: Int, total: Int, progress: @escaping ProgressHandler) {
        guard model.runID == runID else { return }
        let completed = model.pages.filter { !$0.text.isEmpty || $0.embeddedTextUsed }.count
        model.phase = .recognizing(current: min(completed, total), total: total)
        progress(total > 0 ? Double(min(completed, total)) / Double(total) : 1)
    }

    private func isApplied(_ page: OCRPageResult) -> Bool {
        model.pages.contains {
            $0.sourceURL.standardizedFileURL == page.sourceURL.standardizedFileURL
                && $0.pageIndex == page.pageIndex
                && (!$0.text.isEmpty || $0.embeddedTextUsed)
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
        model.pages[index].regions = page.content.regions
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
        let raw = page.editedMarkdown.isEmpty ? (page.markdown ?? page.text) : page.editedMarkdown
        return try write(text: OCRPostprocess.sanitizeFigureURLs(raw), extension: "md", source: page.sourceURL)
    }

    func exportAllMarkdown() throws -> URL {
        let bodies = model.pages.map {
            $0.editedMarkdown.isEmpty ? ($0.markdown ?? $0.text) : $0.editedMarkdown
        }
        let stripped = OCRPostprocess.stripRunningHeaders(bodies)
        // Real embedded images per source page, appended as local references.
        var imageRefs: [[String]] = []
        if let source = model.sources.first,
           Catalog.kind(for: source.url) == .pdf {
            let dir = OutputLocation.directory(beside: source.url)
            imageRefs = (try? PDFImageExtractor.extractImages(
                from: source.url, into: dir,
                baseName: OutputLocation.baseName(source.url))) ?? []
        }
        // Region figures: crop from the rendered page, save beside the export.
        let regionRefs = saveRegionFigures(pages: model.pages)
        let markdown = stripped.enumerated().map { index, body in
            var section = "<!-- page \(index + 1) -->\n\n\(OCRPostprocess.sanitizeFigureURLs(body))"
            if index < imageRefs.count {
                for ref in imageRefs[index] {
                    section += "\n\n![Figure](\(ref))"
                }
            }
            if index < regionRefs.count {
                for ref in regionRefs[index] {
                    section += "\n\n![Figure](\(ref))"
                }
            }
            return section
        }.joined(separator: "\n\n---\n\n")
        let base = model.sources.first?.url ?? URL(fileURLWithPath: "OCR.md")
        return try write(text: markdown, extension: "md", source: base)
    }

    /// Crops figure regions from rendered pages into `<base>-regions/`.
    /// Returns relative paths aligned with model.pages.
    private func saveRegionFigures(pages: [OCRWorkspaceModel.PageState]) -> [[String]] {
        guard let sourceURL = model.sources.first?.url else { return [] }
        let dir = OutputLocation.directory(beside: sourceURL)
        let base = OutputLocation.baseName(sourceURL)
        let folder = dir.appendingPathComponent("\(base)-regions", isDirectory: true)
        var out: [[String]] = []
        for page in pages {
            let figs = page.regions.filter { $0.kind == .figure }
            guard !figs.isEmpty else {
                out.append([])
                continue
            }
            guard let image = try? OCRDocumentSource(url: page.sourceURL)
                .renderImage(pageIndex: page.pageIndex, maxSide: 1600)
            else {
                out.append([])
                continue
            }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var paths: [String] = []
            for (i, region) in figs.enumerated() {
                let rect = CGRect(
                    x: region.bounds.minX * CGFloat(image.width),
                    y: region.bounds.minY * CGFloat(image.height),
                    width: region.bounds.width * CGFloat(image.width),
                    height: region.bounds.height * CGFloat(image.height)
                ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                guard rect.width >= 32, rect.height >= 32,
                      let crop = image.cropping(to: rect)
                else { continue }
                let name = "p\(page.pageIndex + 1)-fig\(i + 1).png"
                let dest = folder.appendingPathComponent(name)
                guard (try? ImageEngine.write(crop, to: dest, as: .png, quality: 1.0)) != nil else { continue }
                paths.append("\(base)-regions/\(name)")
            }
            out.append(paths)
        }
        return out
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
