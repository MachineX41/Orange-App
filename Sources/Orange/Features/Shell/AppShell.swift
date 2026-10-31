import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppShell: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        @Bindable var runtime = runtime
        ZStack {
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 248)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if runtime.localWheel != nil {
                WheelOverlay()
            }
        }
        .background(OrangeTheme.canvas)
        .background(WindowChrome())
        .preferredColorScheme(runtime.appearance.colorScheme)
        .fileImporter(
            isPresented: $runtime.importerPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
            }
            runtime.importURLs(urls)
        }
        .sheet(item: $runtime.sheet) { route in
            EditorSheet(route: route)
        }
        .alert(
            "Orange",
            isPresented: Binding(
                get: { runtime.alertText != nil },
                set: { if !$0 { runtime.alertText = nil } }
            )
        ) {
            Button(Copy.close, role: .cancel) {}
        } message: {
            Text(runtime.alertText ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch runtime.section {
        case .home:
            HomeView()
        case .library:
            LibraryView()
        case .tools:
            ToolsView()
        }
    }
}

struct Sidebar: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(OrangeTheme.accentGradient)
                        .frame(width: 36, height: 36)
                    Circle()
                        .strokeBorder(.white.opacity(0.92), lineWidth: 1.6)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(.white)
                        .frame(width: 4, height: 4)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Orange")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OrangeTheme.ink)
                    Text(Copy.fileStudio)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OrangeTheme.muted)
                }
            }
            .padding(.top, 28)

            VStack(spacing: 4) {
                nav(.home, Copy.home, "square.grid.2x2")
                nav(.library, Copy.library, "clock")
                nav(.tools, Copy.tools, "slider.horizontal.3")
            }

            Spacer()

            if runtime.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(Copy.working)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OrangeTheme.muted)
                }
            }

            SettingsLink {
                Label(Copy.settings, systemImage: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OrangeTheme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(OrangeTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(OrangeTheme.line).frame(width: 1)
        }
    }

    private func nav(_ section: Section, _ title: String, _ symbol: String) -> some View {
        let selected = runtime.section == section
        return Button {
            runtime.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(selected ? OrangeTheme.ink : OrangeTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? OrangeTheme.accent.opacity(0.16) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MenuBarView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(Copy.open) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        if runtime.jobs.isEmpty {
            Text(Copy.emptyLibrary)
        } else {
            ForEach(runtime.jobs.prefix(5)) { job in
                Button(job.title) {
                    let urls = job.outputPaths.map { URL(fileURLWithPath: $0) }
                    if urls.isEmpty {
                        openWindow(id: "main")
                        runtime.section = .library
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting(urls)
                    }
                }
            }
        }
        Divider()
        Button(Copy.quit) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
