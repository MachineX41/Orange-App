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
                Item(keys: ["esc"], title: L("Release the key to cancel", "Vazgeçmek için tuşu bırakın"))
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
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Keyboard Shortcuts", "Klavye Kısayolları"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(L("Everything in Orange works from the keyboard.", "Orange’daki her şey klavyeden de çalışır."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField(L("Search", "Ara"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .padding(20)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(filtered) { group in
                        card(group)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .animation(.easeOut(duration: 0.2), value: query)
            }

            HStack {
                Text(L("Tip: open this list any time with ⌘/.", "İpucu: bu listeyi istediğiniz an ⌘/ ile açın."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(L("Done", "Bitti")) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(OrangeTheme.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 720, height: 560)
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
