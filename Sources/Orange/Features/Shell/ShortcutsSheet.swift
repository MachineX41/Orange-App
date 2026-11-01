import OrangeKit
import SwiftUI

struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Item: Identifiable {
        var keys: [String]
        var title: String
        var id: String { title + keys.joined() }
    }

    private struct Group: Identifiable {
        var title: String
        var symbol: String
        var items: [Item]
        var id: String { title }
    }

    private var groups: [Group] {
        [
            Group(title: L("General", "Genel"), symbol: "command", items: [
                Item(keys: ["⌘", "O"], title: L("Open files", "Dosya aç")),
                Item(keys: ["⌘", "⌫"], title: L("Clear selection", "Seçimi temizle")),
                Item(keys: ["⇧", "⌘", "L"], title: L("Floating shelf", "Yüzen raf")),
                Item(keys: ["⌘", AppDelegate.settingsKey], title: L("Settings", "Ayarlar")),
                Item(keys: ["⌘", "/"], title: L("Keyboard shortcuts", "Klavye kısayolları"))
            ]),
            Group(title: L("Navigate", "Gezinme"), symbol: "sidebar.left", items: [
                Item(keys: ["⌘", "1"], title: L("Home", "Ana Sayfa")),
                Item(keys: ["⌘", "2"], title: L("Download", "İndir")),
                Item(keys: ["⌘", "3"], title: L("Library", "Kitaplık")),
                Item(keys: ["⌘", "4"], title: L("Shelf", "Raf"))
            ] + MediaKind.toolKinds.enumerated().map { index, kind in
                Item(keys: ["⌘", "\(index + 5)"], title: kind.title)
            }),
            Group(title: L("Drag wheel, anywhere", "Sürükleme çarkı, her yerde"), symbol: "hand.draw", items: WheelMode.allCases.map { mode in
                Item(keys: [mode.key], title: L("Hold while dragging: \(mode.title)", "Sürüklerken basılı tut: \(mode.title)"))
            } + [
                Item(keys: ["⇧⌘⌃"], title: L("Release to cancel", "Bırakınca iptal olur"))
            ]),
            Group(title: L("Wheel in this window", "Pencerede çark"), symbol: "circle.dashed", items: WheelMode.allCases.map { mode in
                Item(keys: ["⌘", String(mode.menuKey.character).uppercased()], title: L("\(mode.title) wheel for selection", "Seçim için \(mode.title) çarkı"))
            } + [
                Item(keys: ["←", "→"], title: L("Move between slices", "Dilimler arasında gez")),
                Item(keys: ["↩"], title: L("Choose slice", "Dilimi seç")),
                Item(keys: ["esc"], title: L("Close wheel", "Çarkı kapat"))
            ]),
            Group(title: L("Editors", "Editörler"), symbol: "slider.horizontal.3", items: [
                Item(keys: ["Space"], title: L("Play / pause", "Oynat / duraklat")),
                Item(keys: ["I"], title: L("Set in point", "Başlangıç noktası")),
                Item(keys: ["O"], title: L("Set out point", "Bitiş noktası")),
                Item(keys: ["S"], title: L("Split at playhead", "Oynatma noktasında böl")),
                Item(keys: ["F"], title: L("Add current frame", "Geçerli kareyi ekle")),
                Item(keys: ["B"], title: L("Bleep at playhead", "Oynatma noktasına bip")),
                Item(keys: ["M"], title: L("Compare before / after", "Önce / sonra karşılaştır")),
                Item(keys: ["⌘", "Z"], title: L("Undo mark", "İşareti geri al")),
                Item(keys: ["⌫"], title: L("Delete selected pages", "Seçili sayfaları sil")),
                Item(keys: ["↩"], title: L("Apply", "Uygula")),
                Item(keys: ["esc"], title: L("Cancel", "Vazgeç"))
            ])
        ]
    }

    private var filtered: [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            let items = group.items.filter { $0.title.lowercased().contains(needle) || $0.keys.joined().lowercased().contains(needle) }
            return items.isEmpty ? nil : Group(title: group.title, symbol: group.symbol, items: items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Keyboard Shortcuts", "Klavye Kısayolları"))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(L("Everything in Orange works from the keyboard.", "Orange’daki her şey klavyeden de çalışır."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(L("Search", "Ara"), text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 210)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 16)

            if filtered.isEmpty {
                EmptyHint(
                    symbol: "keyboard",
                    title: L("No shortcuts", "Kısayol yok"),
                    message: L("Nothing matches that search.", "Bu aramayla eşleşen bir kısayol yok.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                        ForEach(filtered) { group in
                            card(group)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                    .animation(.easeOut(duration: 0.2), value: query)
                }
                .scrollContentBackground(.hidden)
            }

            HStack {
                Text(L("Tip: open this list any time with ⌘/.", "İpucu: bu listeyi istediğiniz an ⌘/ ile açın."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("Done", "Bitti")) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(OrangeTheme.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .frame(width: 760, height: 580)
        .background(OrangeBackdrop())
        .presentationBackground { OrangeBackdrop() }
        .background(ShortcutsChrome())
    }

    private func card(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: group.title, symbol: group.symbol)
            VStack(spacing: 7) {
                ForEach(group.items) { item in
                    HStack {
                        Text(item.title)
                            .font(.system(size: 12.5))
                        Spacer(minLength: 10)
                        KeyCombo(keys: item.keys)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
        .transition(.opacity)
    }
}

/// Drops the system sheet fill so the same warm backdrop as the main panel shows through.
private struct ShortcutsChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { Self.apply(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(nsView.window) }
    }

    private static func apply(_ window: NSWindow?) {
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.titlebarSeparatorStyle = .none
    }
}
