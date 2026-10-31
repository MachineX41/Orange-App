import AppKit
import OrangeKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        @Bindable var runtime = runtime
        TabView {
            Form {
                Section(L("Appearance", "Görünüm")) {
                    Picker(L("Theme", "Tema"), selection: $runtime.appearance) {
                        Text(L("System", "Sistem")).tag(AppearanceChoice.system)
                        Text(L("Light", "Açık")).tag(AppearanceChoice.light)
                        Text(L("Dark", "Koyu")).tag(AppearanceChoice.dark)
                    }
                    .pickerStyle(.segmented)
                    Toggle(L("Show Orange in the menu bar", "Orange’ı menü çubuğunda göster"), isOn: $runtime.showInMenuBar)
                }
                Section(L("When a job finishes", "Bir iş bittiğinde")) {
                    Toggle(L("Play a sound", "Ses çal"), isOn: $runtime.soundOnDone)
                    Toggle(L("Reveal the result in Finder", "Sonucu Finder’da göster"), isOn: $runtime.revealWhenDone)
                }
                Section(L("Output", "Çıktı")) {
                    LabeledContent(L("Save results", "Sonuçları kaydet")) {
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(runtime.customOutputPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? L("Next to the original", "Orijinalin yanına"))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack {
                                Button(L("Choose Folder…", "Klasör Seç…")) { chooseFolder() }
                                if runtime.customOutputPath != nil {
                                    Button(L("Use Original Folder", "Orijinal Klasörü Kullan")) { runtime.customOutputPath = nil }
                                }
                            }
                        }
                    }
                    LabeledContent(L("Default image quality", "Varsayılan görsel kalitesi")) {
                        HStack {
                            Slider(value: $runtime.imageQuality, in: 0.4...1).frame(width: 160).tint(OrangeTheme.accent)
                            Text("\(Int(runtime.imageQuality * 100))%").monospacedDigit().frame(width: 40)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label(L("General", "Genel"), systemImage: "gearshape") }

            Form {
                Section(L("Drag wheel", "Sürükleme çarkı")) {
                    Toggle(L("Show the wheel while dragging files", "Dosya sürüklerken çarkı göster"), isOn: $runtime.wheelEnabled)
                    Toggle(L("Haptic feedback on slices", "Dilimlerde dokunsal geri bildirim"), isOn: $runtime.hapticOnWheel)
                }
                Section(L("How it works", "Nasıl çalışır")) {
                    ForEach(WheelMode.allCases, id: \.self) { mode in
                        HStack(spacing: 10) {
                            KeyCap(text: mode.key)
                            Text(mode.title).bold()
                            Spacer()
                            Text(description(mode)).foregroundStyle(.secondary)
                        }
                    }
                    Text(L("Start dragging any file, in Finder or any app, then press a key. The wheel opens where your pointer is and stays fixed until you let go. Drop the file on a slice. Releasing elsewhere cancels.", "Finder’da ya da herhangi bir uygulamada bir dosyayı sürüklemeye başlayın, sonra tuşa basın. Çark imlecin olduğu yerde açılır ve bırakana kadar sabit kalır. Dosyayı bir dilimin üzerine bırakın. Başka bir yere bırakırsanız iptal olur."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label(L("Wheel", "Çark"), systemImage: "circle.circle") }
        }
        .frame(width: 560, height: 440)
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
            .keyboardShortcut(",")
        Button(L("Hide from Menu Bar", "Menü Çubuğundan Gizle")) { runtime.showInMenuBar = false }
        Button(L("Quit Orange", "Orange’dan Çık")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show() {
        runtime.openWindowAction = openWindow
        runtime.showMainWindow()
    }
}
