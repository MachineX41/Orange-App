import AppKit
import OrangeKit
import SwiftUI

struct DownloadView: View {
    @Environment(AppRuntime.self) private var runtime
    @State var link = ""
    @State var audioOnly = false

    private var downloads: [JobRecord] {
        runtime.jobs.filter { $0.symbol == "arrow.down.circle" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: L("Download", "İndir"), subtitle: L("Save video, audio and images from a link.", "Bir linkten video, ses ve görsel kaydedin."), symbol: "arrow.down.circle")
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundStyle(.secondary)
                        TextField(L("Paste a link", "Bir link yapıştırın"), text: $link)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .onSubmit(start)
                        if !link.isEmpty {
                            Button { link = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    HStack {
                        Picker("", selection: $audioOnly) {
                            Label(L("Video", "Video"), systemImage: "film").tag(false)
                            Label(L("Audio", "Ses"), systemImage: "waveform").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                        Button(L("Paste", "Yapıştır")) {
                            if let text = NSPasteboard.general.string(forType: .string) { link = text }
                        }
                        .buttonStyle(.glass).tint(nil)
                        Spacer()
                        Button(action: start) {
                            Label(L("Download", "İndir"), systemImage: "arrow.down")
                        }
                        .buttonStyle(.glassProminent)
                        .tint(OrangeTheme.accent)
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                    .controlSize(.large)
                    Divider().opacity(0.5)
                    HStack(spacing: 10) {
                        if let path = LinkDownloader.downloaderPath {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            Text(L("yt-dlp found at \(path). Most video sites are supported.", "yt-dlp bulundu: \(path). Çoğu video sitesi desteklenir."))
                        } else {
                            Image(systemName: "info.circle.fill").foregroundStyle(OrangeTheme.accent)
                            Text(L("Direct links and pages with embedded media work now. For YouTube, Instagram, X and more, install yt-dlp:", "Doğrudan linkler ve gömülü medyalı sayfalar çalışır. YouTube, Instagram, X ve fazlası için yt-dlp kurun:"))
                            Text("brew install yt-dlp")
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .glassEffect(.regular, in: Capsule())
                                .textSelection(.enabled)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding(22)
                .glassCard(radius: 26)

                if !downloads.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: L("Downloads", "İndirilenler"), symbol: "tray.and.arrow.down")
                        ForEach(downloads) { job in
                            JobRow(job: job, progress: runtime.progress[job.id])
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    private func start() {
        let raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let audioOnly = audioOnly
        let directory = OutputLocation.customDirectory ?? OutputLocation.downloads
        runtime.run(L("Download", "İndir"), symbol: "arrow.down.circle", detail: raw) { progress in
            try await LinkDownloader.download(raw, audioOnly: audioOnly, into: directory, progress: progress)
        }
        link = ""
    }
}
