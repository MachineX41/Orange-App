import OrangeKit
import SwiftUI

/// Model library in Settings › Models: search + installed filter, total disk
/// readout, one primary action per row, inline progress with checksum phase.
struct OCRModelsView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var manager = OCRModelManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    title: L("Models", "Modeller"),
                    subtitle: L("On-device OCR engines. Downloads start only when you tap them.", "Cihaz-içi OCR motorları. İndirmeler yalnızca dokunduğunuzda başlar."),
                    symbol: "cpu"
                )
                HStack(spacing: 10) {
                    TextField(L("Search", "Ara"), text: $manager.query)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Toggle(L("Installed", "Kurulu"), isOn: $manager.installedOnly)
                    Spacer(minLength: 0)
                    Text(diskText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.filtered) { row in
                    rowView(row)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .onAppear { manager.refresh() }
    }

    private var diskText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return L("On disk: \(formatter.string(fromByteCount: manager.totalBytes))", "Diskte: \(formatter.string(fromByteCount: manager.totalBytes))")
    }

    private func rowView(_ row: OCRModelManager.Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.entry.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(purposeText(row.entry))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(metaText(row.entry))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                primaryButton(row)
            }
            if case .downloading(let received, let total) = row.state {
                ProgressView(value: total > 0 ? Double(received) / Double(total) : 0)
                    .tint(OrangeTheme.accent)
                Text(progressText(received: received, total: total))
                    .font(.system(size: 11.5, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if case .verifying = row.state {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("Verifying checksum…", "Sağlama denetleniyor…"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if case .failed(let message, _) = row.state {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(OrangeTheme.ember)
                    .textSelection(.enabled)
            }
            if let perf = perfText(row.entry) {
                Text(perf)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            if let score = row.entry.scoreNote {
                Text(score)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else if row.entry.id != .appleVision {
                Text(L("No verified accuracy number.", "Doğrulanmış doğruluk sayısı yok."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard(radius: 18)
        .accessibilityElement(children: .combine)
    }

    private func purposeText(_ entry: OCRModelEntry) -> String {
        if entry.id == .appleVision {
            return L("Default. Text + documents, OS-managed.", "Varsayılan. Metin + belgeler, sistem yönetimli.")
        }
        let modes = entry.modes.map { $0.rawValue }.joined(separator: " + ")
        let size = ByteCountFormatter.string(fromByteCount: entry.totalBytes, countStyle: .file)
        return "\(modes) · \(size)"
    }

    /// Measured on-device figures from docs/BENCHMARK.md (12-page article, Metal).
    private func perfText(_ entry: OCRModelEntry) -> String? {
        switch entry.id {
        case .appleVision:
            return nil
        case .glmOCR:
            return L("~2.2 GB RAM · ~23s/page · compact output", "~2,2 GB RAM · ~23sn/sayfa · özlü çıktı")
        case .paddleOCRVL16:
            return L("~2.2 GB RAM · ~9s/page · fastest, Metal only", "~2,2 GB RAM · ~9sn/sayfa · en hızlı, yalnız Metal")
        case .qwen3VL2B:
            return L("~3.8 GB RAM · ~36s/page · most complete", "~3,8 GB RAM · ~36sn/sayfa · en eksiksiz")
        case .dotsOCR:
            return L("~3.8 GB RAM · ~91s/page · slowest", "~3,8 GB RAM · ~91sn/sayfa · en yavaş")
        case .deepseekOCR2:
            return L("~4.4 GB RAM · ~21s/page · heaviest", "~4,4 GB RAM · ~21sn/sayfa · en ağır")
        }
    }

    private func metaText(_ entry: OCRModelEntry) -> String {
        var parts: [String] = []
        parts.append(entry.sourceRepo)
        parts.append(entry.license)
        parts.append(entry.provenance == "community" ? L("community mirror", "topluluk aynası") : entry.provenance)
        parts.append(entry.languageClaim)
        return parts.joined(separator: " · ")
    }

    private func progressText(received: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let percent = total > 0 ? Int((Double(received) / Double(total) * 100).rounded()) : 0
        return "\(formatter.string(fromByteCount: received)) / \(formatter.string(fromByteCount: total)) · \(percent)%"
    }

    @ViewBuilder
    private func primaryButton(_ row: OCRModelManager.Row) -> some View {
        switch row.state {
        case .notInstalled:
            Button(L("Download", "İndir")) { manager.primaryAction(for: row) }
                .buttonStyle(.glass).controlSize(.small)
        case .downloading:
            Button(L("Cancel", "İptal")) { manager.primaryAction(for: row) }
                .buttonStyle(.glass).controlSize(.small)
                .accessibilityLabel(L("Cancel", "İptal"))
        case .paused:
            Menu {
                Button(L("Resume", "Devam Et")) { manager.primaryAction(for: row) }
                Button(L("Delete partial files", "Yarım Dosyaları Sil"), role: .destructive) {
                    manager.deletePartial(for: row.entry)
                }
            } label: {
                Text(L("Resume", "Devam Et"))
            }
            .buttonStyle(.glass).controlSize(.small)
        case .verifying:
            ProgressView().controlSize(.small)
        case .installed:
            Menu {
                Button(L("Use", "Kullan")) { manager.activate(row.entry) }
                if row.entry.id != .appleVision {
                    Button(L("Delete", "Sil"), role: .destructive) {
                        manager.deleteInstalled(for: row.entry)
                    }
                }
            } label: {
                Text(L("Installed", "Kurulu"))
            }
            .buttonStyle(.glass).controlSize(.small)
            .disabled(row.entry.id == .appleVision ? false : runtime.ocrWorkspace.isRunning)
        case .failed(_, let canResume):
            Button(canResume ? L("Retry", "Yeniden Dene") : L("Download", "İndir")) {
                manager.primaryAction(for: row)
            }
            .buttonStyle(.glass).controlSize(.small)
        }
    }
}
