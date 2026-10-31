import SwiftUI

@main
struct OrangeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtime = AppRuntime.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            AppShell()
                .environment(runtime)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(Copy.openFiles) {
                    AppRuntime.shared.importerPresented = true
                }
                .keyboardShortcut("o")
                Button(Copy.sample) {
                    AppRuntime.shared.useSample()
                }
            }
            CommandGroup(after: .sidebar) {
                Button(Copy.home) { AppRuntime.shared.section = .home }
                    .keyboardShortcut("1")
                Button(Copy.library) { AppRuntime.shared.section = .library }
                    .keyboardShortcut("2")
                Button(Copy.tools) { AppRuntime.shared.section = .tools }
                    .keyboardShortcut("3")
            }
        }

        Settings {
            SettingsView()
                .environment(runtime)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(runtime)
        } label: {
            Image(systemName: "o.circle.fill")
        }
    }
}
