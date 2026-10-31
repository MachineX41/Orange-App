import AppKit
import OrangeKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppRuntime.self) private var runtime
    @State var query = ""

    private var jobs: [JobRecord] {
        guard !query.isEmpty else { return runtime.jobs }
        return runtime.jobs.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PageHeader(title: L("Library", "Kitaplık"), subtitle: L("Everything Orange has made for you.", "Orange’ın sizin için ürettiği her şey."), symbol: "clock.arrow.circlepath")
                TextField(L("Search", "Ara"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Button(L("Clear History", "Geçmişi Temizle")) { runtime.clearHistory() }
                    .buttonStyle(.glass).tint(nil)
                    .disabled(runtime.jobs.isEmpty)
            }
            if jobs.isEmpty {
                EmptyHint(symbol: "tray", title: L("Nothing here yet", "Henüz bir şey yok"), message: L("Converted and edited files show up here.", "Dönüştürülen ve düzenlenen dosyalar burada görünür."))
                    .glassCard(radius: 26)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(jobs) { job in
                            JobRow(job: job, progress: runtime.progress[job.id])
                        }
                    }
                    .padding(2)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(28)
    }
}

struct JobRow: View {
    var job: JobRecord
    var progress: Double?

    private var outputs: [URL] { job.outputPaths.map { URL(fileURLWithPath: $0) } }

    var body: some View {
        HStack(spacing: 14) {
            if let first = outputs.first, FileManager.default.fileExists(atPath: first.path) {
                FileThumbnail(url: first, side: 44, radius: 9)
            } else {
                Image(systemName: job.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OrangeTheme.accent)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title).font(.system(size: 13.5, weight: .semibold))
                Text(job.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(job.state == .failure ? OrangeTheme.ember : .secondary)
                    .lineLimit(2)
            }
            Spacer()
            switch job.state {
            case .running:
                ProgressView(value: progress ?? 0).frame(width: 90).tint(OrangeTheme.accent)
            case .success:
                Text(job.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.glass).tint(nil)
                .buttonBorderShape(.circle)
                .help(L("Reveal in Finder", "Finder’da Göster"))
            case .failure:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(OrangeTheme.ember)
            }
        }
        .padding(12)
        .glassCard(radius: 18)
        .onDrag {
            NSItemProvider(contentsOf: outputs.first) ?? NSItemProvider()
        }
        .contextMenu {
            if !outputs.isEmpty {
                Button(L("Open", "Aç")) { outputs.forEach { NSWorkspace.shared.open($0) } }
                Button(L("Reveal in Finder", "Finder’da Göster")) { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
                Button(L("Use as Input", "Girdi Olarak Kullan")) { AppRuntime.shared.importURLs(outputs) }
            }
        }
    }
}

struct ShelfView: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PageHeader(title: L("Shelf", "Raf"), subtitle: L("Park files here, then drag them out anywhere.", "Dosyaları burada bekletin, sonra istediğiniz yere sürükleyin."), symbol: "tray.full")
                Button(L("Floating Shelf", "Yüzen Raf")) { FloatShelf.shared.toggle() }
                    .buttonStyle(.glass).tint(nil)
                Button(L("Clear", "Temizle")) { runtime.clearShelf() }
                    .buttonStyle(.glass).tint(nil)
                    .disabled(runtime.shelf.isEmpty)
            }
            if runtime.shelf.isEmpty {
                EmptyHint(symbol: "tray", title: L("The shelf is empty", "Raf boş"), message: L("Use the Shelf action in the ⌃ wheel, or drop files on the floating shelf.", "⌃ çarkındaki Raf eylemini kullanın ya da dosyaları yüzen rafa bırakın."))
                    .glassCard(radius: 26)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 16) {
                        ForEach(runtime.shelf) { file in
                            VStack(spacing: 6) {
                                FileThumbnail(url: file.url, side: 96, radius: 14)
                                Text(file.name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            }
                            .padding(10)
                            .glassCard(radius: 18)
                            .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
                            .contextMenu {
                                Button(L("Use as Input", "Girdi Olarak Kullan")) { runtime.importURLs([file.url]) }
                                Button(L("Reveal in Finder", "Finder’da Göster")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                                Button(L("Remove", "Kaldır")) { runtime.removeFromShelf(file) }
                            }
                        }
                    }
                    .padding(2)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(28)
    }
}
