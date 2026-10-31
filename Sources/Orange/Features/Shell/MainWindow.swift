import OrangeKit
import SwiftUI

struct MainWindow: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow
    @State var dropTargeted = false

    var body: some View {
        @Bindable var runtime = runtime
        NavigationSplitView {
            List(selection: Binding<AppSection?>(get: { runtime.section }, set: { if let value = $0 { runtime.section = value } })) {
                Section {
                    Label(L("Home", "Ana Sayfa"), systemImage: "house").tag(AppSection.home)
                    Label(L("Download", "İndir"), systemImage: "arrow.down").tag(AppSection.download)
                    Label(L("Library", "Kitaplık"), systemImage: "clock").tag(AppSection.library)
                    Label(L("Shelf", "Raf"), systemImage: "tray")
                        .badge(runtime.shelf.count)
                        .tag(AppSection.shelf)
                }
                Section(L("Tools", "Araçlar")) {
                    ForEach(MediaKind.toolKinds) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(AppSection.tools(kind))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
        } detail: {
            ZStack {
                OrangeBackdrop()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(runtime.section)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(OrangeTheme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .padding(14)
                        .allowsHitTesting(false)
                }
                if let session = runtime.localWheel {
                    LocalWheelOverlay(session: session)
                        .transition(.opacity)
                        .id(session.id)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                runtime.importURLs(urls)
                return !urls.isEmpty
            } isTargeted: { dropTargeted = $0 }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    FloatShelf.shared.toggle()
                } label: {
                    Label(L("Floating Shelf", "Yüzen Raf"), systemImage: "tray.and.arrow.down")
                }
                .help(L("Floating Shelf", "Yüzen Raf"))
                Button {
                    runtime.openFiles()
                } label: {
                    Label(L("Open Files", "Dosya Aç"), systemImage: "plus")
                }
                .help(L("Open Files (⌘O)", "Dosya Aç (⌘O)"))
                Button {
                    runtime.showShortcuts = true
                } label: {
                    Label(L("Keyboard Shortcuts", "Klavye Kısayolları"), systemImage: "keyboard")
                }
                .help(L("Keyboard Shortcuts (⌘/)", "Klavye Kısayolları (⌘/)"))
            }
        }
        .sheet(isPresented: $runtime.showShortcuts) { ShortcutsSheet() }
        .animation(.easeOut(duration: 0.22), value: runtime.section)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: runtime.localWheel)
        .onAppear { runtime.openWindowAction = openWindow }
    }

    @ViewBuilder private var detail: some View {
        switch runtime.section {
        case .home: HomeView()
        case .download: DownloadView()
        case .library: LibraryView()
        case .shelf: ShelfView()
        case .tools(let kind): ToolsView(kind: kind)
        }
    }
}

/// Wraps children onto new lines when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

struct PageHeader: View {
    var title: String
    var subtitle: String
    var symbol: String? = nil
    var brand = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if brand {
                OrangeMark(side: 40)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
