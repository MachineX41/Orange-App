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
            }
            CommandMenu(L("Wheel", "Çark")) {
                ForEach(WheelMode.allCases, id: \.self) { mode in
                    Button(L("\(mode.title) Wheel", "\(mode.title) Çarkı")) { runtime.presentLocalWheel(mode) }
                        .disabled(runtime.selection.isEmpty)
                }
                Divider()
                Button(L("Floating Shelf", "Yüzen Raf")) { FloatShelf.shared.toggle() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button(L("Home", "Ana Sayfa")) { runtime.section = .home }.keyboardShortcut("1")
                Button(L("Download", "İndir")) { runtime.section = .download }.keyboardShortcut("2")
                Button(L("Library", "Kitaplık")) { runtime.section = .library }.keyboardShortcut("3")
                Button(L("Shelf", "Raf")) { runtime.section = .shelf }.keyboardShortcut("4")
            }
        }

        Settings {
            SettingsView()
                .environment(runtime)
                .preferredColorScheme(runtime.appearance.colorScheme)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(runtime)
        } label: {
            OrangeMark(side: 18)
        }
    }
}
