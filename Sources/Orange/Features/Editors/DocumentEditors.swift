import AppKit
import OrangeKit
import SwiftUI

// MARK: Metadata

struct MetadataEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var fields: [MetadataField] = []
    @State var loading = true
    @State var hasLocation = false
    @State var query = ""

    private var groups: [(String, [MetadataField])] {
        let filtered = query.isEmpty ? fields : fields.filter {
            $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query)
        }
        var order: [String] = []
        var map: [String: [MetadataField]] = [:]
        for field in filtered {
            if map[field.group] == nil { order.append(field.group) }
            map[field.group, default: []].append(field)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Remove Metadata", "Meta Veriyi Temizle"), canApply: Catalog.kind(for: url) != .other, apply: apply) {
            if loading {
                ProgressView().controlSize(.large)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.0) { group, items in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(group.uppercased())
                                    .font(.system(size: 10.5, weight: .bold))
                                    .tracking(0.6)
                                    .foregroundStyle(OrangeTheme.accent)
                                    .padding(.bottom, 6)
                                ForEach(items) { field in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(field.key)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 200, alignment: .leading)
                                        Text(field.value)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.system(size: 12.5))
                                    .padding(.vertical, 5)
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .environment(\.colorScheme, .dark)
            }
        } inspector: {
            InspectorSection(title: L("File", "Dosya"), symbol: "doc") {
                HStack {
                    Spacer()
                    FileThumbnail(url: url, side: 150, radius: 16)
                    Spacer()
                }
                TextField(L("Search fields", "Alanlarda ara"), text: $query)
                    .textFieldStyle(.roundedBorder)
                InfoRow(title: L("Fields", "Alan"), value: "\(fields.count)")
            }
            InspectorSection(title: L("Privacy", "Gizlilik"), symbol: "hand.raised") {
                if hasLocation {
                    Label(L("This photo contains its GPS location.", "Bu fotoğraf GPS konumunu içeriyor."), systemImage: "location.fill")
                        .font(.callout)
                        .foregroundStyle(OrangeTheme.ember)
                } else {
                    Label(L("No location data found.", "Konum verisi bulunamadı."), systemImage: "checkmark.shield")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(L("Removing creates a clean copy without camera, location and author details.", "Temizleme; kamera, konum ve yazar bilgisi olmadan temiz bir kopya oluşturur."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Button {
                let text = fields.map { "\($0.group) · \($0.key): \($0.value)" }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                runtime.toast(L("Copied", "Kopyalandı"), L("\(fields.count) fields", "\(fields.count) alan"), symbol: "doc.on.clipboard", style: .info)
            } label: {
                Label(L("Copy All", "Tümünü Kopyala"), systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.glass).tint(nil)
        }
        .task {
            fields = await MetadataKit.fields(of: url)
            hasLocation = MetadataKit.hasLocation(url)
            loading = false
        }
    }

    private func apply() {
        let url = url
        runtime.run(L("Remove Metadata", "Meta Veriyi Temizle"), symbol: editor.tool.symbol, detail: url.lastPathComponent) { progress in
            [try await MetadataKit.strip(url, progress: progress)]
        }
        editor.close()
    }
}

// MARK: QR & barcodes

struct CodeReaderEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var urls: [URL]
    @State var hits: [BarcodeHit] = []
    @State var scanning = true

    private var openable: [(hit: BarcodeHit, action: CodeAction)] {
        hits.compactMap { hit in
            let action = CodeAction.parse(hit.payload)
            return action.url == nil ? nil : (hit, action)
        }
    }

    private var single: CodeAction? {
        openable.count == 1 ? openable[0].action : nil
    }

    var body: some View {
        EditorScaffold(primaryTitle: single.map(\.verb) ?? L("Copy All", "Tümünü Kopyala"), canApply: !hits.isEmpty, busy: scanning, apply: primary) {
            if scanning {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(L("Scanning…", "Taranıyor…")).foregroundStyle(.white.opacity(0.7))
                }
            } else if hits.isEmpty {
                EmptyHint(symbol: "qrcode.viewfinder", title: L("No codes found", "Kod bulunamadı"), message: L("Try a sharper or larger image.", "Daha net ya da büyük bir görsel deneyin."))
                    .environment(\.colorScheme, .dark)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(hits) { hit in
                            CodeHitRow(hit: hit, action: CodeAction.parse(hit.payload)) { perform($0) }
                        }
                    }
                    .padding(22)
                }
                .environment(\.colorScheme, .dark)
            }
        } inspector: {
            InspectorSection(title: L("Scanned", "Taranan"), symbol: "doc.viewfinder") {
                ForEach(urls, id: \.self) { url in
                    HStack {
                        FileThumbnail(url: url, side: 30, radius: 6)
                        Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                }
                InfoRow(title: L("Codes", "Kod"), value: "\(hits.count)")
                if !openable.isEmpty {
                    InfoRow(title: L("Links", "Bağlantı"), value: "\(openable.count)")
                }
            }
            InspectorSection(title: L("Safety", "Güvenlik"), symbol: "checkmark.shield") {
                Text(L("Codes never open on their own. Check the address shown under each code before you open it.", "Kodlar kendiliğinden açılmaz. Açmadan önce her kodun altındaki adresi kontrol edin."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            let urls = urls
            hits = await Task.detached { urls.flatMap { (try? BarcodeReader.scan(url: $0)) ?? [] } }.value
            scanning = false
        }
    }

    private func primary() {
        if let single {
            perform(single)
            editor.close()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hits.map(\.payload).joined(separator: "\n"), forType: .string)
        runtime.toast(L("Copied", "Kopyalandı"), L("\(hits.count) code(s)", "\(hits.count) kod"), symbol: "qrcode", style: .info)
        editor.close()
    }

    private func perform(_ action: CodeAction) {
        switch action {
        case .wifi(let ssid, let password):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(password ?? ssid, forType: .string)
            runtime.toast(
                password == nil ? L("Network name copied", "Ağ adı kopyalandı") : L("Wi‑Fi password copied", "Wi‑Fi şifresi kopyalandı"),
                ssid,
                symbol: "wifi",
                style: .info
            )
        case .text:
            break
        default:
            if let url = action.url { NSWorkspace.shared.open(url) }
        }
    }
}

extension CodeAction {
    var verb: String {
        switch self {
        case .web: L("Go to Link", "Bağlantıya Git")
        case .email: L("Write Email", "E‑posta Yaz")
        case .phone: L("Call", "Ara")
        case .message: L("Send Message", "Mesaj Gönder")
        case .map: L("Open in Maps", "Haritada Aç")
        case .wifi(_, let password): password == nil ? L("Copy Network", "Ağı Kopyala") : L("Copy Password", "Şifreyi Kopyala")
        case .text: L("Copy", "Kopyala")
        }
    }

    var symbol: String {
        switch self {
        case .web: "safari"
        case .email: "envelope"
        case .phone: "phone"
        case .message: "message"
        case .map: "map"
        case .wifi: "wifi"
        case .text: "text.alignleft"
        }
    }

    var kindTitle: String {
        switch self {
        case .web: L("Website", "Web sitesi")
        case .email: L("Email", "E‑posta")
        case .phone: L("Phone", "Telefon")
        case .message: L("Message", "Mesaj")
        case .map: L("Location", "Konum")
        case .wifi: L("Wi‑Fi network", "Wi‑Fi ağı")
        case .text: L("Text", "Metin")
        }
    }
}

private struct CodeHitRow: View {
    var hit: BarcodeHit
    var action: CodeAction
    var perform: (CodeAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: hit.symbology.lowercased().contains("qr") ? "qrcode" : "barcode")
                .font(.system(size: 26))
                .foregroundStyle(OrangeTheme.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(hit.payload)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(4)
                    .textSelection(.enabled)
                if action != .text {
                    HStack(spacing: 6) {
                        Image(systemName: action.symbol)
                        Text(action.kindTitle)
                        if let destination = action.destination {
                            Text("·")
                            Text(destination).fontWeight(.semibold).foregroundStyle(.primary)
                        }
                        if action.isInsecure {
                            Label(L("Not secure", "Güvenli değil"), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text([hit.symbology, hit.source, hit.page.map { L("page \($0)", "sayfa \($0)") }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if action != .text {
                Button(action.verb) { perform(action) }
                    .buttonStyle(.glassProminent)
                    .tint(OrangeTheme.accent)
                    .help(action.url?.absoluteString ?? "")
            }
            Button(L("Copy", "Kopyala")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hit.payload, forType: .string)
            }
            .buttonStyle(.glass)
            .tint(nil)
        }
        .padding(16)
        .glassCard(radius: 18)
    }
}

// MARK: Merge PDFs

struct MergePDFEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    @State var urls: [URL]
    @State var pages: [URL: Int] = [:]

    init(urls: [URL]) {
        _urls = State(initialValue: urls)
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Merge", "Birleştir"), canApply: urls.count >= 2, apply: apply) {
            List {
                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(OrangeTheme.accent)
                            .frame(width: 22)
                        FileThumbnail(url: url, side: 56, radius: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(L("\(pages[url] ?? 0) pages", "\(pages[url] ?? 0) sayfa")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { urls.removeAll { $0 == url } } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                }
                .onMove { source, destination in urls.move(fromOffsets: source, toOffset: destination) }
            }
            .scrollContentBackground(.hidden)
            .environment(\.colorScheme, .dark)
            .padding(10)
        } inspector: {
            InspectorSection(title: L("Document", "Belge"), symbol: "doc.on.doc") {
                InfoRow(title: L("Files", "Dosya"), value: "\(urls.count)")
                InfoRow(title: L("Total pages", "Toplam sayfa"), value: "\(urls.reduce(0) { $0 + (pages[$1] ?? 0) })")
                Text(L("Drag rows to change the order.", "Sırayı değiştirmek için satırları sürükleyin."))
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { urls += await runtime.chooseFiles(kinds: [.pdf]) }
                } label: {
                    Label(L("Add PDFs…", "PDF Ekle…"), systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).tint(nil)
            }
        }
        .task(id: urls) {
            for url in urls where pages[url] == nil {
                pages[url] = (try? PDFToolkit.pageCount(of: url)) ?? 0
            }
        }
    }

    private func apply() {
        let urls = urls
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: L("\(urls.count) files", "\(urls.count) dosya")) { _ in
            [try PDFToolkit.merge(urls: urls, into: OutputLocation.directory(beside: urls[0]))]
        }
        editor.close()
    }
}

// MARK: Page thumbnails

@MainActor
@Observable
final class PDFPages {
    var images: [CGImage] = []
    var loading = true

    func load(_ url: URL) async {
        images = await Task.detached { (try? PDFToolkit.thumbnails(of: url, maxSide: 260)) ?? [] }.value
        loading = false
    }
}

struct PageTile: View {
    var image: CGImage?
    var number: Int
    var rotation: Int = 0
    var tint: Color?
    var selected = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(Double(rotation)))
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                }
            }
            .frame(width: 120, height: 150)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill((tint ?? .white).opacity(tint == nil ? 0.04 : 0.22)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? OrangeTheme.accent : .clear, lineWidth: 3))
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

// MARK: Split

enum SplitChoice: String, Hashable { case every, ranges, chunks }

struct SplitPDFEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var pages = PDFPages()
    @State var choice: SplitChoice = .every
    @State var ranges = "1-2, 3-"
    @State var chunk = 2

    private var parsed: [ClosedRange<Int>]? {
        let count = pages.images.count
        guard count > 0 else { return nil }
        switch choice {
        case .every: return (1...count).map { $0...$0 }
        case .chunks: return stride(from: 1, through: count, by: chunk).map { $0...min($0 + chunk - 1, count) }
        case .ranges: return try? PDFToolkit.parsePageSelection(ranges, pageCount: count)
        }
    }

    private static let groupColors: [Color] = [.orange, .pink, .purple, .blue, .teal, .green, .yellow]

    var body: some View {
        EditorScaffold(primaryTitle: L("Split", "Böl"), canApply: (parsed?.isEmpty == false), apply: apply) {
            if pages.loading {
                ProgressView().controlSize(.large)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 16) {
                        ForEach(Array(pages.images.enumerated()), id: \.offset) { index, image in
                            PageTile(image: image, number: index + 1, tint: tint(for: index + 1))
                        }
                    }
                    .padding(22)
                }
            }
        } inspector: {
            InspectorSection(title: L("Split By", "Bölme Şekli"), symbol: "scissors") {
                ChoiceGrid(options: [(SplitChoice.every, L("Each Page", "Her Sayfa")), (.ranges, L("Ranges", "Aralık")), (.chunks, L("Every N", "Her N"))], selection: $choice)
                switch choice {
                case .ranges:
                    TextField("1-3, 5, 8-", text: $ranges)
                        .textFieldStyle(.roundedBorder)
                    if parsed == nil {
                        Label(OrangeError.invalidPages.message, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(OrangeTheme.ember)
                    }
                case .chunks:
                    Stepper(L("\(chunk) pages per file", "Dosya başına \(chunk) sayfa"), value: $chunk, in: 1...max(1, pages.images.count))
                case .every:
                    EmptyView()
                }
            }
            InspectorSection(title: L("Result", "Sonuç"), symbol: "doc.on.doc") {
                InfoRow(title: L("Pages", "Sayfa"), value: "\(pages.images.count)")
                InfoRow(title: L("New files", "Yeni dosya"), value: "\(parsed?.count ?? 0)")
            }
        }
        .task { await pages.load(url) }
    }

    private func tint(for page: Int) -> Color? {
        guard let groups = parsed, let index = groups.firstIndex(where: { $0.contains(page) }) else { return nil }
        return Self.groupColors[index % Self.groupColors.count]
    }

    private func apply() {
        let url = url
        let mode: SplitMode = switch choice {
        case .every: .everyPage
        case .ranges: .ranges(ranges)
        case .chunks: .chunks(chunk)
        }
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            let outputs = try PDFToolkit.split(url: url, mode: mode, into: OutputLocation.directory(beside: url))
            return outputs.first.map { [$0.deletingLastPathComponent()] } ?? []
        }
        editor.close()
    }
}

// MARK: Organize

struct PageItem: Identifiable, Hashable {
    let id: Int
    var rotation = 0
}

struct OrganizePDFEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var pages = PDFPages()
    @State var items: [PageItem] = []
    @State var selection: Set<Int> = []

    private var changed: Bool {
        items.map(\.id) != Array(0..<pages.images.count) || items.contains { $0.rotation != 0 }
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Save Copy", "Kopyayı Kaydet"), canApply: changed && !items.isEmpty, apply: apply) {
            if pages.loading {
                ProgressView().controlSize(.large)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 16) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            PageTile(image: pages.images[safe: item.id], number: index + 1, rotation: item.rotation, selected: selection.contains(item.id))
                                .onTapGesture {
                                    if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                                        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                                    } else {
                                        selection = [item.id]
                                    }
                                }
                                .draggable(String(item.id))
                                .dropDestination(for: String.self) { dropped, _ in
                                    guard let id = dropped.first.flatMap(Int.init), let from = items.firstIndex(where: { $0.id == id }),
                                          let to = items.firstIndex(where: { $0.id == item.id }) else { return false }
                                    withAnimation(.snappy) {
                                        let moved = items.remove(at: from)
                                        items.insert(moved, at: to)
                                    }
                                    return true
                                }
                        }
                    }
                    .padding(22)
                    .animation(.snappy, value: items)
                }
            }
        } inspector: {
            InspectorSection(title: L("Selected Pages", "Seçili Sayfalar"), symbol: "hand.tap") {
                Text(selection.isEmpty ? L("Click a page; ⌘-click to pick more.", "Bir sayfaya tıklayın; çoklu seçim için ⌘.") : L("\(selection.count) selected", "\(selection.count) seçili"))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button { rotate(-90) } label: { Label(L("Left", "Sola"), systemImage: "rotate.left") }
                    Button { rotate(90) } label: { Label(L("Right", "Sağa"), systemImage: "rotate.right") }
                }
                .disabled(selection.isEmpty)
                HStack {
                    Button { shift(-1) } label: { Label(L("Earlier", "Öne"), systemImage: "arrow.left") }
                    Button { shift(1) } label: { Label(L("Later", "Sona"), systemImage: "arrow.right") }
                }
                .disabled(selection.count != 1)
                Button(role: .destructive) {
                    withAnimation { items.removeAll { selection.contains($0.id) } }
                    selection.removeAll()
                } label: {
                    Label(L("Delete", "Sil"), systemImage: "trash").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selection.isEmpty || selection.count >= items.count)
            }
            .buttonStyle(.glass).tint(nil)
            InspectorSection(title: L("Document", "Belge"), symbol: "doc") {
                InfoRow(title: L("Pages", "Sayfa"), value: "\(items.count) / \(pages.images.count)")
                Text(L("Drag pages to reorder.", "Sıralamak için sayfaları sürükleyin.")).font(.caption).foregroundStyle(.secondary)
                Button(L("Reset", "Sıfırla")) {
                    items = (0..<pages.images.count).map { PageItem(id: $0) }
                    selection.removeAll()
                }
                .buttonStyle(.glass).tint(nil)
            }
        }
        .task {
            await pages.load(url)
            items = (0..<pages.images.count).map { PageItem(id: $0) }
        }
    }

    private func rotate(_ degrees: Int) {
        for index in items.indices where selection.contains(items[index].id) {
            items[index].rotation = (items[index].rotation + degrees + 360) % 360
        }
    }

    private func shift(_ delta: Int) {
        guard let id = selection.first, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }

    private func apply() {
        let edits = items.map { PageEdit(source: $0.id, rotation: $0.rotation) }
        let url = url
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            [try PDFToolkit.organize(url: url, pages: edits)]
        }
        editor.close()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
