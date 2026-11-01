import AppKit
import OrangeKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        @Bindable var runtime = runtime
        TabView {
            SettingsPage {
                SettingsGroup(title: L("Appearance", "Görünüm"), symbol: "circle.lefthalf.filled") {
                    SettingsRow(title: L("Language", "Dil")) {
                        Picker(L("Language", "Dil"), selection: $runtime.language) {
                            Text(L("System", "Sistem")).tag(LanguageChoice.system)
                            Text("Türkçe").tag(LanguageChoice.turkish)
                            Text("English").tag(LanguageChoice.english)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 280)
                    }
                    SettingsRow(title: L("Theme", "Tema")) {
                        Picker(L("Theme", "Tema"), selection: $runtime.appearance) {
                            Text(L("System", "Sistem")).tag(AppearanceChoice.system)
                            Text(L("Light", "Açık")).tag(AppearanceChoice.light)
                            Text(L("Dark", "Koyu")).tag(AppearanceChoice.dark)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    SettingsToggle(title: L("Show Orange in the menu bar", "Orange’ı menü çubuğunda göster"), isOn: $runtime.showInMenuBar)
                }
                SettingsGroup(title: L("When a job finishes", "Bir iş bittiğinde"), symbol: "checkmark.circle") {
                    SettingsToggle(title: L("Play a sound", "Ses çal"), isOn: $runtime.soundOnDone)
                    SettingsToggle(title: L("Reveal the result in Finder", "Sonucu Finder’da göster"), isOn: $runtime.revealWhenDone)
                }
                SettingsGroup(title: L("Output", "Çıktı"), symbol: "folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Save results", "Sonuçları kaydet"))
                            .font(.system(size: 13, weight: .medium))
                        Text(runtime.customOutputPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? L("Next to the original", "Orijinalin yanına"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 8) {
                            Button(L("Choose Folder…", "Klasör Seç…")) { chooseFolder() }
                            if runtime.customOutputPath != nil {
                                Button(L("Use Original Folder", "Orijinal Klasörü Kullan")) { runtime.customOutputPath = nil }
                            }
                        }
                        .buttonStyle(.glass)
                        .tint(nil)
                    }
                    SettingsRow(title: L("Default image quality", "Varsayılan görsel kalitesi")) {
                        HStack(spacing: 8) {
                            Slider(value: $runtime.imageQuality, in: 0.4...1).frame(width: 150).tint(OrangeTheme.accent)
                            Text("\(Int(runtime.imageQuality * 100))%").monospacedDigit().font(.system(size: 12, weight: .medium)).frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            .tabItem { Label(L("General", "Genel"), systemImage: "gearshape") }

            SettingsPage {
                SettingsGroup(title: L("Drag wheel", "Sürükleme çarkı"), symbol: "circle.circle") {
                    SettingsToggle(title: L("Show the wheel while dragging files", "Dosya sürüklerken çarkı göster"), isOn: $runtime.wheelEnabled)
                    SettingsToggle(title: L("Haptic feedback on slices", "Dilimlerde dokunsal geri bildirim"), isOn: $runtime.hapticOnWheel)
                }
                SettingsGroup(title: L("How it works", "Nasıl çalışır"), symbol: "hand.draw") {
                    ForEach(WheelMode.allCases, id: \.self) { mode in
                        HStack(spacing: 10) {
                            KeyCap(text: mode.key)
                            Text(mode.title).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(description(mode)).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Text(L("Start dragging any file, in Finder or any app, then press a key. The wheel opens where your pointer is and stays fixed until you let go. Drop the file on a slice. Releasing elsewhere cancels.", "Finder’da ya da herhangi bir uygulamada bir dosyayı sürüklemeye başlayın, sonra tuşa basın. Çark imlecin olduğu yerde açılır ve bırakana kadar sabit kalır. Dosyayı bir dilimin üzerine bırakın. Başka bir yere bırakırsanız iptal olur."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tabItem { Label(L("Wheel", "Çark"), systemImage: "circle.circle") }

            PrivacySettings()
                .tabItem { Label(L("Privacy", "Gizlilik"), systemImage: "hand.raised") }
        }
        .tint(OrangeTheme.accent)
        .frame(width: 640, height: 560)
        .background(OrangeBackdrop())
        .background(SettingsChrome())
    }

    private func description(_ mode: WheelMode) -> String {
        switch mode {
        case .convert: L("Change format", "Biçim değiştir")
        case .tools: L("Edit and process", "Düzenle ve işle")
        case .actions: L("Move, share and organize", "Taşı, paylaş, düzenle")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Use Folder", "Klasörü Kullan")
        if panel.runModal() == .OK, let url = panel.url {
            runtime.customOutputPath = url.path
        }
    }
}

struct PrivacySettings: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var permissions = Permissions.shared
    @State private var confirmClear = false

    var body: some View {
        SettingsPage {
            SettingsGroup(title: L("Folder access", "Klasör erişimi"), symbol: "folder.badge.gearshape") {
                ForEach(ProtectedFolder.allCases) { folder in
                    FolderRow(folder: folder)
                        .padding(.horizontal, -16)
                }
                Text(L("macOS shows its own prompt the first time. Declined folders can be turned on in System Settings › Privacy & Security › Files & Folders.", "macOS ilk seferde kendi onay penceresini gösterir. Reddedilen klasörler Sistem Ayarları › Gizlilik ve Güvenlik › Dosyalar ve Klasörler’den açılabilir."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsGroup(title: L("Startup", "Başlangıç"), symbol: "power") {
                SettingsToggle(title: L("Open Orange at login", "Orange’ı girişte aç"), isOn: Binding(get: { permissions.opensAtLogin }, set: { permissions.setOpensAtLogin($0) }))
                if permissions.loginItem == .requiresApproval {
                    Text(L("Approve Orange under System Settings › General › Login Items.", "Sistem Ayarları › Genel › Giriş Öğeleri’nden Orange’ı onaylayın."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if let error = permissions.loginItemError {
                    Text(error).font(.system(size: 12)).foregroundStyle(OrangeTheme.ember)
                }
            }
            SettingsGroup(title: L("Your data", "Verileriniz"), symbol: "lock") {
                SettingsFact(title: L("Processing", "İşleme"), value: L("On this Mac only", "Yalnızca bu Mac’te"))
                SettingsFact(title: L("Analytics and tracking", "Analiz ve takip"), value: L("None", "Yok"))
                if let date = Consent.acceptedAt {
                    SettingsFact(title: L("Terms accepted", "Koşullar kabul edildi"), value: date.formatted(date: .abbreviated, time: .shortened))
                }
                HStack(spacing: 14) {
                    Link(L("Privacy Notice", "Gizlilik Bildirimi"), destination: Consent.privacyURL)
                    Link(L("Terms of Use", "Kullanım Koşulları"), destination: Consent.termsURL)
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OrangeTheme.accent)
                HStack(spacing: 8) {
                    Button(L("Clear History and Shelf…", "Geçmişi ve Rafı Temizle…")) { confirmClear = true }
                    Button(L("Show Welcome Tour", "Tanıtımı Göster")) { runtime.replayOnboarding() }
                }
                .buttonStyle(.glass)
                .tint(nil)
            }
        }
        .onAppear { permissions.refreshLoginItem() }
        .confirmationDialog(L("Clear history and shelf?", "Geçmiş ve raf temizlensin mi?"), isPresented: $confirmClear) {
            Button(L("Clear", "Temizle"), role: .destructive) {
                runtime.clearHistory()
                runtime.clearShelf()
            }
        } message: {
            Text(L("Your files stay where they are. Only Orange’s list of them is removed.", "Dosyalarınız yerinde kalır. Yalnızca Orange’ın onlara ait listesi silinir."))
        }
    }
}

/// Scrollable settings page on the same warm backdrop as the main panel.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(OrangeBackdrop())
    }
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: title, symbol: symbol)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 18)
        }
    }
}

private struct SettingsRow<Control: View>: View {
    var title: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 12)
            control()
        }
    }
}

private struct SettingsToggle: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(OrangeTheme.accent)
        }
    }
}

private struct SettingsFact: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }
}

/// Clears the system window fill so the panel backdrop shows through the Settings window.
private struct SettingsChrome: NSViewRepresentable {
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
    }
}

struct MenuBarView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var runtime = runtime
        Button(L("Open Orange", "Orange’ı Aç")) { show() }
        Button(L("Open Files…", "Dosya Aç…")) {
            show()
            runtime.openFiles()
        }
        Button(L("Floating Shelf", "Yüzen Raf")) { FloatShelf.shared.toggle() }

        Divider()
        Toggle(L("Drag Wheel", "Sürükleme Çarkı"), isOn: $runtime.wheelEnabled)
        Text(L("Drag a file and hold ⇧ Convert, ⌘ Tools or ⌃ Actions", "Dosyayı sürükleyip ⇧ Dönüştür, ⌘ Araçlar ya da ⌃ Eylemler’e basılı tutun"))

        if !runtime.running.isEmpty {
            Divider()
            Section(L("Working", "Çalışıyor")) {
                ForEach(runtime.running) { job in
                    Text("\(job.title) · \(Int((runtime.progress[job.id] ?? 0) * 100))%")
                }
            }
        }

        let recent = Array(runtime.recentOutputs.prefix(5))
        if !recent.isEmpty {
            Divider()
            Menu(L("Recent Results", "Son Sonuçlar")) {
                ForEach(recent, id: \.self) { url in
                    Button(url.lastPathComponent) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Divider()
                Button(L("Show Library", "Kitaplığı Göster")) {
                    runtime.section = .library
                    show()
                }
            }
        }

        Divider()
        Button(L("Keyboard Shortcuts", "Klavye Kısayolları")) {
            show()
            runtime.showShortcuts = true
        }
        SettingsLink { Text(L("Settings…", "Ayarlar…")) }
        Button(L("Hide from Menu Bar", "Menü Çubuğundan Gizle")) { runtime.showInMenuBar = false }
        Button(L("Quit Orange", "Orange’dan Çık")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show() {
        runtime.openWindowAction = openWindow
        runtime.showMainWindow()
    }
}
