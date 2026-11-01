import OrangeKit
import SwiftUI

struct MainWindow: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow
    @Namespace private var sidebarSelection
    @State var dropTargeted = false

    var body: some View {
        @Bindable var runtime = runtime
        NavigationSplitView {
            List {
                Section {
                    SidebarItem(section: .home, title: L("Home", "Ana Sayfa"), symbol: "house", namespace: sidebarSelection)
                    SidebarItem(section: .ocr, title: L("Text (OCR)", "Metin (OCR)"), symbol: "text.viewfinder", namespace: sidebarSelection)
                    SidebarItem(section: .download, title: L("Download", "İndir"), symbol: "arrow.down", namespace: sidebarSelection)
                    SidebarItem(section: .library, title: L("Library", "Kitaplık"), symbol: "clock", namespace: sidebarSelection)
                    SidebarItem(section: .shelf, title: L("Shelf", "Raf"), symbol: "tray", badge: runtime.shelf.count, namespace: sidebarSelection)
                }
                Section(L("Tools", "Araçlar")) {
                    ForEach(MediaKind.toolKinds) { kind in
                        SidebarItem(section: .tools(kind), title: kind.title, symbol: kind.symbol, namespace: sidebarSelection)
                    }
                }
            }
            .listStyle(.sidebar)
            .tint(OrangeTheme.accent)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: runtime.section)
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
                if runtime.section == .ocr {
                    let supported = urls.filter { [.image, .pdf].contains(Catalog.kind(for: $0)) }
                    guard !supported.isEmpty else {
                        runtime.toast(L("Text (OCR)", "Metin (OCR)"), L("Only images and PDFs can be used here.", "Burada yalnızca görsel ve PDF kullanılabilir."), symbol: "text.viewfinder", style: .info)
                        return false
                    }
                    runtime.ocrWorkspace.add(urls: supported)
                    return true
                }
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
        .background {
            Color.clear
                .sheet(isPresented: $runtime.showOnboarding) {
                    OnboardingView { runtime.finishOnboarding() }
                        .environment(runtime)
                }
        }
        .animation(.easeOut(duration: 0.22), value: runtime.section)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: runtime.localWheel)
        .onAppear { runtime.openWindowAction = openWindow }
    }

    @ViewBuilder private var detail: some View {
        switch runtime.section {
        case .home: HomeView()
        case .ocr: OCRWorkspace()
        case .download: DownloadView()
        case .library: LibraryView()
        case .shelf: ShelfView()
        case .tools(let kind): ToolsView(kind: kind)
        }
    }
}

/// Sidebar row whose selection is Orange, rather than the system accent.
struct SidebarItem: View {
    @Environment(AppRuntime.self) private var runtime
    var section: AppSection
    var title: String
    var symbol: String
    var badge = 0
    var namespace: Namespace.ID
    @State private var hovered = false

    private var selected: Bool { runtime.section == section }

    var body: some View {
        Button {
            runtime.section = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(selected ? Color.white : OrangeTheme.accent)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.white.opacity(0.92) : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(OrangeTheme.accent)
                        .matchedGeometryEffect(id: "sidebarSelection", in: namespace)
                } else if hovered {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
