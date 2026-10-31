import AppKit
import OrangeKit
import SwiftUI

struct HomeView: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Orange",
                    subtitle: L("Convert, edit and move files right where you drag them.", "Dosyaları sürüklediğiniz yerde dönüştürün, düzenleyin, taşıyın."),
                    brand: true
                )
                Group {
                    if runtime.selection.isEmpty {
                        DropZone()
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        SelectionPanel()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: runtime.selection.isEmpty)
                HowItWorks()
                if !runtime.recentOutputs.isEmpty {
                    RecentStrip(urls: runtime.recentOutputs)
                }
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
        .scrollContentBackground(.hidden)
    }
}

struct DropZone: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce.down, options: .repeat(.periodic(delay: 3.5)))
            VStack(spacing: 5) {
                Text(L("Drop files to begin", "Başlamak için dosya bırakın"))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(L("Images, video, audio, PDFs, documents and archives", "Görsel, video, ses, PDF, belge ve arşivler"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    runtime.openFiles()
                } label: {
                    Label(L("Choose Files…", "Dosya Seç…"), systemImage: "folder")
                }
                .buttonStyle(.glassProminent)
                .tint(OrangeTheme.accent)
                Button {
                    runtime.useSample()
                } label: {
                    Label(L("Try a Sample", "Örnek Dene"), systemImage: "sparkles")
                }
                .buttonStyle(.glass).tint(nil)
            }
            .controlSize(.large)
            HStack(spacing: 6) {
                Text(L("or press", "ya da"))
                KeyCombo(keys: ["⌘", "O"])
                Text(L("· drop anywhere in this window", "· bu pencerede herhangi bir yere bırakın"))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .glassCard(radius: 30)
    }
}

struct SelectionPanel: View {
    @Environment(AppRuntime.self) private var runtime

    private var urls: [URL] { runtime.selection.map(\.url) }

    var body: some View {
        let targets = Catalog.commonConvertTargets(for: urls)
        let tools = Catalog.commonTools(for: urls)
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("\(runtime.selection.count) selected", "\(runtime.selection.count) seçili"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(ByteCountFormatter.string(fromByteCount: runtime.selection.reduce(0) { $0 + $1.byteCount }, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(WheelMode.allCases, id: \.self) { mode in
                            Button {
                                runtime.presentLocalWheel(mode)
                            } label: {
                                HStack(spacing: 6) {
                                    Label(mode.title, systemImage: mode.symbol)
                                    Text(mode.menuKeyText)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.glass).tint(nil)
                            .help(L("Open the \(mode.title) wheel (\(mode.menuKeyText))", "\(mode.title) çarkını aç (\(mode.menuKeyText))"))
                        }
                    }
                }
                Button {
                    runtime.openFiles()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glass).tint(nil)
                .buttonBorderShape(.circle)
                .help(L("Add Files", "Dosya Ekle"))
                Button {
                    withAnimation { runtime.selection.removeAll() }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass).tint(nil)
                .buttonBorderShape(.circle)
                .help(L("Clear Selection (⌘⌫)", "Seçimi Temizle (⌘⌫)"))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(runtime.selection) { file in
                        FileChip(file: file)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)

            if !targets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: L("Convert to", "Dönüştür"), symbol: "arrow.triangle.2.circlepath")
                    FlowLayout(spacing: 8) {
                        ForEach(targets) { target in
                            Button {
                                runtime.convert(runtime.selection, to: target)
                            } label: {
                                Label(target.title, systemImage: target.symbol)
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .buttonStyle(.glass).tint(nil)
                        }
                    }
                }
            }

            if !tools.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: L("Tools", "Araçlar"), symbol: "wrench.and.screwdriver")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(tools) { tool in
                            Button {
                                runtime.open(tool, files: runtime.selection)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: tool.symbol)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22)
                                    Text(tool.title).font(.system(size: 13, weight: .medium))
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: L("Actions", "Eylemler"), symbol: "bolt")
                FlowLayout(spacing: 8) {
                    ForEach(ActionID.allCases, id: \.self) { action in
                        Button {
                            runtime.perform(action, files: runtime.selection)
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .buttonStyle(.glass).tint(nil)
                    }
                }
            }
        }
        .padding(22)
        .glassCard(radius: 28)
    }
}

struct FileChip: View {
    @Environment(AppRuntime.self) private var runtime
    var file: FileRef

    var body: some View {
        VStack(spacing: 7) {
            FileThumbnail(url: file.url, side: 86, radius: 14)
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation { runtime.remove(file) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            VStack(spacing: 1) {
                Text(file.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.sizeText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 104)
        .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
        .contextMenu {
            Button(L("Reveal in Finder", "Finder’da Göster")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Button(L("Open", "Aç")) { NSWorkspace.shared.open(file.url) }
            Divider()
            Button(L("Remove", "Kaldır")) { runtime.remove(file) }
        }
    }
}

struct RecentStrip: View {
    var urls: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: L("Recent results", "Son sonuçlar"), symbol: "clock")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(urls, id: \.self) { url in
                        VStack(spacing: 6) {
                            FileThumbnail(url: url, side: 78, radius: 12)
                            Text(url.lastPathComponent)
                                .font(.system(size: 10.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(width: 92)
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .contextMenu {
                            Button(L("Reveal in Finder", "Finder’da Göster")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Button(L("Use as Input", "Girdi Olarak Kullan")) { AppRuntime.shared.importURLs([url]) }
                        }
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.never)
            .glassCard(radius: 22)
        }
    }
}
