import OrangeKit
import SwiftUI

/// Persistent OCR workspace: sources rail, preview, and editable results.
/// Owned by AppRuntime so tab switches never lose input or running jobs.
struct OCRWorkspace: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var runner: OCRRunner?
    @State private var wide = true

    private var model: OCRWorkspaceModel { runtime.ocrWorkspace }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: L("Text (OCR)", "Metin (OCR)"),
                    subtitle: L("Apple on-device or downloaded local models. Nothing uploads.", "Apple cihaz-içi veya indirilen yerel modeller. Hiçbir şey yüklenmez."),
                    symbol: "text.viewfinder"
                )
                controls
                statusLine
                GeometryReader { proxy in
                    content(wide: proxy.size.width >= 820)
                        .onAppear { wide = proxy.size.width >= 820 }
                        .onChange(of: proxy.size.width) { _, width in wide = width >= 820 }
                }
                .frame(minHeight: 420)
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(L("Add Files", "Dosya Ekle")) { addFiles() }
                    .disabled(model.isRunning)
                Button(L("Manage Models", "Modelleri Yönet")) { openModels() }
            }
        }
        .onAppear { if runner == nil { runner = OCRRunner(runtime: runtime) } }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Picker(L("Model", "Model"), selection: Binding(
                get: { model.options.modelID },
                set: { setModel($0) }
            )) {
                ForEach(availableModels, id: \.id) { entry in
                    Text(entry.displayName).tag(entry.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isRunning)
            .frame(maxWidth: 200)

            Picker(L("Language", "Dil"), selection: Binding(
                get: { languageTag },
                set: { setLanguage($0) }
            )) {
                Text(L("Auto", "Otomatik")).tag("")
                Text("Türkçe").tag("tr")
                Text("English").tag("en")
                Text(L("Turkish + English", "Türkçe + İngilizce")).tag("tr+en")
            }
            .pickerStyle(.menu)
            .disabled(model.isRunning)
            .frame(maxWidth: 190)

            Picker(L("Mode", "Mod"), selection: Binding(
                get: { model.options.mode },
                set: { setMode($0) }
            )) {
                ForEach(supportedModes, id: \.self) { mode in
                    Text(modeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)
            .frame(maxWidth: 220)

            Picker(L("Compute", "Hesaplama"), selection: Binding(
                get: { model.options.compute },
                set: { setCompute($0) }
            )) {
                Text(L("Auto", "Otomatik")).tag(OCRComputePreference.automatic)
                Text("Metal").tag(OCRComputePreference.metal)
                Text("CPU").tag(OCRComputePreference.cpu)
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning || model.options.modelID == .appleVision)
            .frame(maxWidth: 240)
            .help(model.options.modelID == .appleVision ? L("OS-managed", "Sistem yönetimli") : "")

            Spacer(minLength: 0)

            if model.isRunning {
                Button(L("Cancel", "İptal")) { runner?.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(L("Cancel", "İptal"))
            } else {
                Button(L("Run", "Çalıştır")) { runner?.run() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.sources.isEmpty)
            }
        }
        .glassCard(radius: 20)
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            statusSymbol
            Text(statusText)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(model.activeComputeLabel)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var statusSymbol: some View {
        Group {
            switch model.phase {
            case .idle: Image(systemName: "text.viewfinder").foregroundStyle(.secondary)
            case .preparing, .loadingModel: ProgressView().controlSize(.small)
            case .recognizing: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(OrangeTheme.ember)
            }
        }
        .frame(width: 20)
    }

    private var statusText: String {
        switch model.phase {
        case .idle:
            model.sources.isEmpty
                ? L("Add images or a PDF to begin.", "Başlamak için görsel veya PDF ekleyin.")
                : L("\(model.sources.count) file(s) ready.", "\(model.sources.count) dosya hazır.")
        case .preparing: L("Preparing…", "Hazırlanıyor…")
        case .loadingModel: L("Loading model…", "Model yükleniyor…")
        case .recognizing(let current, let total):
            L("Recognizing page \(current)/\(total)…", "Sayfa tanınıyor \(current)/\(total)…")
        case .done: L("Done — \(model.activeModelName)", "Tamamlandı — \(model.activeModelName)")
        case .cancelled: L("Cancelled", "İptal edildi")
        case .failed(let message): message
        }
    }

    // MARK: - Content

    private func content(wide: Bool) -> some View {
        Group {
            if wide {
                HStack(alignment: .top, spacing: 16) {
                    rail.frame(width: 170)
                    previewPanel.frame(maxWidth: .infinity)
                    resultPanel.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 16) {
                    rail.frame(maxWidth: .infinity)
                    TabView(selection: Binding(
                        get: { model.showMarkdown ? 1 : 0 },
                        set: { _ in }
                    )) {
                        previewPanel.tag(0)
                        resultPanel.tag(1)
                    }
                    .tabViewStyle(.automatic)
                    .frame(minHeight: 380)
                }
            }
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: L("Sources", "Kaynaklar"), symbol: "photo.stack")
            if model.sources.isEmpty {
                Text(L("No files yet.", "Henüz dosya yok."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.sources) { source in
                HStack {
                    Text(source.name)
                        .font(.system(size: 12.5))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if !model.isRunning {
                        Button { model.remove(source: source) } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Remove", "Kaldır"))
                    }
                }
                .padding(8)
                .glassCard(radius: 12)
            }
            SectionLabel(title: L("Pages", "Sayfalar"), symbol: "doc.richtext")
            ForEach(model.pages) { page in
                Button {
                    model.selectedPageID = page.id
                } label: {
                    HStack {
                        Text("p\(page.pageIndex + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                        Text(page.text.isEmpty ? L("Empty", "Boş") : String(page.text.prefix(28)))
                            .font(.system(size: 12))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .padding(6)
                }
                .buttonStyle(.plain)
                .background(model.selectedPageID == page.id ? OrangeTheme.accent.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .glassCard(radius: 20)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: L("Preview", "Önizleme"), symbol: "eye")
            ZStack {
                OrangeBackdrop()
                if let page = model.selectedPage {
                    Text(String(page.text.prefix(200)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    Text(L("Select a page.", "Sayfa seçin."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .glassCard(radius: 20)
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(title: L("Result", "Sonuç"), symbol: "text.alignleft")
                Spacer(minLength: 0)
                if hasMarkdown {
                    Picker("", selection: Binding(
                        get: { model.showMarkdown },
                        set: { model.showMarkdown = $0 }
                    )) {
                        Text(L("Text", "Metin")).tag(false)
                        Text("Markdown").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            if let page = model.selectedPage {
                if model.showMarkdown && hasMarkdown {
                    TextEditor(text: Binding(
                        get: { page.editedMarkdown },
                        set: { model.updateMarkdown($0, for: page.id) }
                    ))
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    TextEditor(text: Binding(
                        get: { page.editedText.isEmpty ? page.text : page.editedText },
                        set: { model.updateText($0, for: page.id) }
                    ))
                    .font(.system(size: 13))
                    .frame(minHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if page.stale {
                    Text(L("From a previous run.", "Önceki çalışmanın sonucu."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if page.embeddedTextUsed {
                    Text(L("Native text layer.", "Yerel metin katmanı."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                exportRow(page: page)
            } else {
                Text(L("Run OCR to see results.", "Sonuç için OCR çalıştırın."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(OrangeTheme.ember)
                    .textSelection(.enabled)
            }
        }
        .glassCard(radius: 20)
    }

    private func exportRow(page: OCRWorkspaceModel.PageState) -> some View {
        HStack(spacing: 8) {
            Button(L("Copy", "Kopyala")) { copy(page: page) }
            Button(L("Copy All", "Tümünü Kopyala")) { copyAll() }
            Button(L("Save .txt", ".txt Kaydet")) { saveText(page: page) }
            if hasMarkdown {
                Button(L("Save .md", ".md Kaydet")) { saveMarkdown(page: page) }
            }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(page.text.isEmpty)
    }

    // MARK: - Options plumbing

    private var availableModels: [(id: OCRModelID, displayName: String)] {
        OCRModelCatalog.all.map { ($0.id, $0.displayName) }
    }

    private var languageTag: String {
        let ids = model.options.languageIdentifiers
        if ids.isEmpty { return "" }
        if ids == ["tr"] { return "tr" }
        if ids == ["en"] { return "en" }
        return "tr+en"
    }

    private var hasMarkdown: Bool {
        model.selectedPage?.markdown != nil
    }

    private func modeLabel(_ mode: OCRMode) -> String {
        switch mode {
        case .text: return L("Text", "Metin")
        case .document: return L("Document", "Belge")
        }
    }

    private func setModel(_ id: OCRModelID) {
        model.options.modelID = id
        if !supportedModes.contains(model.options.mode) { model.options.mode = .text }
        runtime.ocrDefaultModelID = id.rawValue
        model.markOptionsChanged()
    }

    private func setMode(_ mode: OCRMode) {
        model.options.mode = mode
        runtime.ocrMode = mode.rawValue
        model.markOptionsChanged()
    }

    private func setCompute(_ compute: OCRComputePreference) {
        model.options.compute = compute
        runtime.ocrComputePreference = compute.rawValue
        model.markOptionsChanged()
    }

    private func setLanguage(_ tag: String) {
        let ids: [String]
        switch tag {
        case "tr": ids = ["tr"]
        case "en": ids = ["en"]
        case "tr+en": ids = ["tr", "en"]
        default: ids = []
        }
        model.options.languageIdentifiers = ids
        runtime.ocrLanguageIdentifiers = ids
        model.markOptionsChanged()
    }

    // MARK: - Actions

    private func addFiles() {
        Task {
            let urls = await runtime.chooseFiles(kinds: [.image, .pdf], multiple: true)
            model.add(urls: urls)
        }
    }

    private func openModels() {
        runtime.settingsTab = .models
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func copy(page: OCRWorkspaceModel.PageState) {
        let text = page.editedText.isEmpty ? page.text : page.editedText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyAll() {
        let text = model.pages.map { $0.editedText.isEmpty ? $0.text : $0.editedText }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveText(page: OCRWorkspaceModel.PageState) {
        do {
            let url = try runner?.exportText(page: page)
            if let url { runtime.toast(L("Saved", "Kaydedildi"), url.lastPathComponent, symbol: "checkmark.circle.fill", style: .success, outputs: [url]) }
        } catch {
            runtime.notify(error)
        }
    }

    private func saveMarkdown(page: OCRWorkspaceModel.PageState) {
        do {
            let url = try runner?.exportMarkdown(page: page)
            if let url { runtime.toast(L("Saved", "Kaydedildi"), url.lastPathComponent, symbol: "checkmark.circle.fill", style: .success, outputs: [url]) }
        } catch {
            runtime.notify(error)
        }
    }
}
