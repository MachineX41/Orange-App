import Foundation
import OrangeKit

/// Download/install state per model for OCRModelsView. Consent-gated: no
/// download starts unless Consent.accepted. One active transfer app-wide.
@MainActor
@Observable
final class OCRModelManager {
    enum RowState: Equatable {
        case notInstalled
        case downloading(received: Int64, total: Int64)
        case paused(received: Int64, total: Int64)
        case verifying
        case installed
        case failed(message: String, canResume: Bool)
    }

    struct Row: Identifiable {
        var entry: OCRModelEntry
        var id: String { entry.id.rawValue }
        var state: RowState = .notInstalled
    }

    var rows: [Row] = OCRModelCatalog.all.map { Row(entry: $0) }
    var query = ""
    var installedOnly = false
    private var downloader: OCRModelDownloader?
    private let store = OCRModelStore()

    var filtered: [Row] {
        rows.filter { row in
            if installedOnly, row.state != .installed { return false }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return row.entry.displayName.lowercased().contains(q)
                || row.entry.sourceRepo.lowercased().contains(q)
        }
    }

    var totalBytes: Int64 {
        rows.reduce(0) { acc, row in
            guard row.state == .installed else { return acc }
            return acc + row.entry.totalBytes
        }
    }

    func refresh() {
        Task {
            for index in rows.indices {
                let entry = rows[index].entry
                if entry.id == .appleVision { rows[index].state = .installed; continue }
                if case .downloading = rows[index].state { continue }
                rows[index].state = await store.status(for: entry) == .installed ? .installed : .notInstalled
            }
        }
    }

    func primaryAction(for row: Row) {
        switch row.state {
        case .notInstalled, .failed:
            startDownload(row.entry)
        case .downloading:
            downloader?.pause()
            setState(.paused(received: receivedOf(row), total: row.entry.totalBytes), for: row.entry.id)
        case .paused:
            startDownload(row.entry)
        case .verifying:
            break
        case .installed:
            activate(row.entry)
        }
    }

    func deletePartial(for entry: OCRModelEntry) {
        Task {
            try? await store.removePartial(entry)
            setState(.notInstalled, for: entry.id)
        }
    }

    func deleteInstalled(for entry: OCRModelEntry) {
        Task {
            try? await store.removeInstalled(entry)
            setState(.notInstalled, for: entry.id)
        }
    }

    func activate(_ entry: OCRModelEntry) {
        // Next job uses the new default; the running inference keeps its snapshot.
        AppRuntime.shared.ocrDefaultModelID = entry.id.rawValue
        AppRuntime.shared.ocrWorkspace.options.modelID = entry.id
    }

    private func receivedOf(_ row: Row) -> Int64 {
        if case .downloading(let received, _) = row.state { return received }
        if case .paused(let received, _) = row.state { return received }
        return 0
    }

    private func setState(_ state: RowState, for id: OCRModelID) {
        guard let index = rows.firstIndex(where: { $0.entry.id == id }) else { return }
        rows[index].state = state
    }

    private func startDownload(_ entry: OCRModelEntry) {
        guard Consent.accepted else { return }
        guard downloader?.isActive != true else { return }
        let downloader = OCRModelDownloader(entry: entry, store: store)
        self.downloader = downloader
        downloader.onPhase = { [weak self] phase in
            Task { @MainActor [weak self] in
                self?.apply(phase, entry: entry)
            }
        }
        downloader.start()
    }

    private func apply(_ phase: OCRModelDownloader.Phase, entry: OCRModelEntry) {
        switch phase {
        case .idle: setState(.notInstalled, for: entry.id)
        case .downloading(let received, let total): setState(.downloading(received: received, total: total), for: entry.id)
        case .paused(let received, let total): setState(.paused(received: received, total: total), for: entry.id)
        case .verifying: setState(.verifying, for: entry.id)
        case .installed: setState(.installed, for: entry.id)
        case .failed(let message, let canResume): setState(.failed(message: message, canResume: canResume), for: entry.id)
        }
    }
}
