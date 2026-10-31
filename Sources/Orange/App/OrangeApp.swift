import OrangeKit
import SwiftUI

@main
struct OrangeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtime = AppRuntime.shared

    var body: some Scene {
        Window("Orange", id: "main") {
            MainWindow()
                .environment(runtime)
                .preferredColorScheme(runtime.appearance.colorScheme)
                .tint(OrangeTheme.accent)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("Open Files…", "Dosya Aç…")) { runtime.openFiles() }
                    .keyboardShortcut("o")
                Button(L("Try a Sample", "Örnek Dene")) { runtime.useSample() }
                Divider()
                Button(L("Clear Selection", "Seçimi Temizle")) { runtime.selection.removeAll() }
                    .keyboardShortcut(.delete)
                    .disabled(runtime.selection.isEmpty)
            }
            CommandMenu(L("Wheel", "Çark")) {
                ForEach(WheelMode.allCases, id: \.self) { mode in
                    Button(L("\(mode.title) Wheel", "\(mode.title) Çarkı")) { runtime.presentLocalWheel(mode) }
                        .keyboardShortcut(mode.menuKey)
                        .disabled(runtime.selection.isEmpty)
                }
                Divider()
                Toggle(L("Drag Wheel Everywhere", "Her Yerde Sürükleme Çarkı"), isOn: Binding(get: { runtime.wheelEnabled }, set: { runtime.wheelEnabled = $0 }))
                Button(L("Floating Shelf", "Yüzen Raf")) { FloatShelf.shared.toggle() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button(L("Home", "Ana Sayfa")) { runtime.section = .home }.keyboardShortcut("1")
                Button(L("Download", "İndir")) { runtime.section = .download }.keyboardShortcut("2")
                Button(L("Library", "Kitaplık")) { runtime.section = .library }.keyboardShortcut("3")
                Button(L("Shelf", "Raf")) { runtime.section = .shelf }.keyboardShortcut("4")
                Divider()
                ForEach(Array(MediaKind.toolKinds.enumerated()), id: \.element) { index, kind in
                    Button(kind.title) { runtime.section = .tools(kind) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 5))))
                }
                Divider()
                Toggle(L("Show in Menu Bar", "Menü Çubuğunda Göster"), isOn: Binding(get: { runtime.showInMenuBar }, set: { runtime.showInMenuBar = $0 }))
            }
            CommandGroup(replacing: .help) {
                Button(L("Keyboard Shortcuts", "Klavye Kısayolları")) {
                    runtime.showMainWindow()
                    runtime.showShortcuts = true
                }
                .keyboardShortcut("/", modifiers: .command, localization: .custom)
                Button(L("Show Welcome Tour", "Tanıtımı Göster")) { runtime.replayOnboarding() }
                Divider()
                Link(L("Privacy Notice", "Gizlilik Bildirimi"), destination: Consent.privacyURL)
                Link(L("Terms of Use", "Kullanım Koşulları"), destination: Consent.termsURL)
                Link(L("Orange on GitHub", "GitHub’da Orange"), destination: URL(string: "https://github.com/MachineX41/Orange-App")!)
            }
        }

        Settings {
            SettingsView()
                .environment(runtime)
                .preferredColorScheme(runtime.appearance.colorScheme)
                .tint(OrangeTheme.accent)
        }

        MenuBarExtra(isInserted: Binding(get: { runtime.showInMenuBar }, set: { runtime.showInMenuBar = $0 })) {
            MenuBarView()
                .environment(runtime)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }
}
