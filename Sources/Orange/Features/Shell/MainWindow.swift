import AppKit
import OrangeKit
import SwiftUI

/// Shared by the welcome tour and the first working window, so one opens into the other.
enum StudioWindow {
    static let width: CGFloat = 960
    static let height: CGFloat = 680
}

struct MainWindow: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow
    @Namespace private var sidebarSelection
    @State var dropTargeted = false

    @State private var host: NSWindow?
    @State private var tourMounted: Bool
    @State private var tourVisible: Bool
    @State private var panelMounted: Bool
    @State private var panelVisible: Bool
    @State private var chromeReady: Bool
    @State private var settled: Bool
    @State private var transitioning = false
    @State private var assemblyMounted = false
    @State private var assemblySlices = 0
    @State private var assemblyLit = false
    @State private var assemblyExiting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        let touring = AppRuntime.shared.showOnboarding
        _tourMounted = State(initialValue: touring)
        _tourVisible = State(initialValue: touring)
        _panelMounted = State(initialValue: !touring)
        _panelVisible = State(initialValue: !touring)
        _chromeReady = State(initialValue: !touring)
        _settled = State(initialValue: !touring)
    }

    var body: some View {
        @Bindable var runtime = runtime
        ZStack {
            OrangeBackdrop()
            if panelMounted {
                panel
                    .opacity(panelVisible ? 1 : 0)
                    .scaleEffect(panelVisible ? 1 : 0.972, anchor: .center)
                    .allowsHitTesting(panelVisible)
            }
            if tourMounted {
                OnboardingView { runtime.finishOnboarding() }
                    .opacity(tourVisible ? 1 : 0)
                    .scaleEffect(tourVisible ? 1 : 0.965, anchor: .center)
                    .allowsHitTesting(tourVisible)
            }
            if assemblyMounted {
                PanelAssembly(revealed: assemblySlices, lit: assemblyLit, exiting: assemblyExiting)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.62, dampingFraction: 0.9), value: tourVisible)
        .animation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.78, dampingFraction: 0.88), value: panelVisible)
        .frame(
            minWidth: StudioWindow.width,
            idealWidth: StudioWindow.width,
            minHeight: StudioWindow.height,
            idealHeight: StudioWindow.height
        )
        .toolbar(chromeReady ? .visible : .hidden, for: .windowToolbar)
        .background(WindowReader { window in
            if host !== window { host = window }
        })
        .onAppear {
            runtime.openWindowAction = openWindow
            if runtime.showOnboarding {
                fitTourWindow(animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { fitTourWindow(animated: false) }
            } else {
                growToDefaultIfSmaller()
            }
        }
        .onChange(of: runtime.showOnboarding) { wasShowing, showing in
            if showing { presentTour() }
            else if wasShowing { revealPanel() }
        }
        .onChange(of: host) { _, _ in
            if runtime.showOnboarding { fitTourWindow(animated: false) }
            else { growToDefaultIfSmaller() }
        }
    }

    /// The working panel. It stays out of the window until the welcome tour finishes.
    private var panel: some View {
        @Bindable var runtime = runtime
        return NavigationSplitView {
            List {
                Section {
                    SidebarItem(section: .home, title: L("Home", "Ana Sayfa"), symbol: "house", namespace: sidebarSelection)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SettingsSidebarButton()
            }
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
    }

    /// Reveals the panel inside the tour window. The window stays at the tour size, so the wheel opens into the panel without a resize.
    private func revealPanel() {
        panelMounted = true
        guard !reduceMotion else {
            tourVisible = false
            tourMounted = false
            panelVisible = true
            showChrome()
            return
        }
        transitioning = true
        assemblySlices = 0
        assemblyLit = false
        assemblyExiting = false
        assemblyMounted = true
        withAnimation(.easeIn(duration: 0.32)) { tourVisible = false }

        let first = 0.26
        let step = 0.075
        for index in 0..<PanelAssembly.sliceCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + first + Double(index) * step) {
                withAnimation(.spring(response: 0.46, dampingFraction: 0.7)) { assemblySlices = index + 1 }
            }
        }
        let built = first + Double(PanelAssembly.sliceCount) * step + 0.12
        DispatchQueue.main.asyncAfter(deadline: .now() + built) {
            withAnimation(.easeOut(duration: 0.3)) { assemblyLit = true }
        }
        let open = built + 0.32
        DispatchQueue.main.asyncAfter(deadline: .now() + open) {
            host?.title = "Orange"
            host?.titleVisibility = .visible
            host?.titlebarAppearsTransparent = false
            tourMounted = false
            withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { assemblyExiting = true }
            withAnimation(.spring(response: 0.82, dampingFraction: 0.88)) { panelVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + open + 0.45) {
            withAnimation(.easeOut(duration: 0.3)) { chromeReady = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + open + 0.95) {
            settled = true
            assemblyMounted = false
            transitioning = false
        }
    }

    /// Shrinks the panel back into the tour when it is replayed.
    private func presentTour() {
        tourMounted = true
        guard !reduceMotion else {
            panelVisible = false
            panelMounted = false
            tourVisible = true
            chromeReady = false
            settled = false
            fitTourWindow(animated: false)
            return
        }
        transitioning = true
        chromeReady = false
        settled = false
        withAnimation(.easeIn(duration: 0.28)) { panelVisible = false }
        fitTourWindow(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) { tourVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            panelMounted = false
            transitioning = false
        }
    }

    private func showChrome() {
        host?.title = "Orange"
        host?.titleVisibility = .visible
        host?.titlebarAppearsTransparent = false
        chromeReady = true
        settled = true
    }

    private func fitTourWindow(animated: Bool) {
        guard let host, !transitioning || animated else { return }
        host.titleVisibility = .hidden
        host.titlebarAppearsTransparent = true
        let target = frame(fittingContent: NSSize(width: StudioWindow.width, height: StudioWindow.height), in: host)
        guard abs(host.frame.width - target.width) > 12 || abs(host.frame.height - target.height) > 12 else { return }
        if animated {
            animate(host, to: target, duration: 0.55)
        } else {
            host.setFrame(target, display: true)
        }
    }

    /// The previous default, 760×560, is below the new opening size. A window still sitting there grows once.
    private func growToDefaultIfSmaller() {
        guard let host else { return }
        let content = host.contentRect(forFrameRect: host.frame).size
        guard content.width < 820, content.height < 620 else { return }
        let target = frame(fittingContent: NSSize(width: StudioWindow.width, height: StudioWindow.height), in: host)
        host.setFrame(target, display: true)
    }

    private func frame(fittingContent size: NSSize, in window: NSWindow) -> NSRect {
        let current = window.contentRect(forFrameRect: window.frame)
        let content = NSRect(
            x: current.midX - size.width / 2,
            y: current.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        var frame = window.frameRect(forContentRect: content)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        return frame
    }

    private func animate(_ window: NSWindow, to frame: NSRect, duration: Double) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.22, 1)
            window.animator().setFrame(frame, display: true)
        }
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

/// The wheel builds itself slice by slice after the tour, lights up, then opens outward into the panel.
private struct PanelAssembly: View {
    static let sliceCount = 8
    var revealed: Int
    var lit: Bool
    var exiting: Bool
    @Environment(\.colorScheme) private var scheme

    private var restFill: Color { scheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.1) }

    var body: some View {
        ZStack {
            ForEach(0..<Self.sliceCount, id: \.self) { index in
                let shown = index < revealed
                let latest = index == revealed - 1 && !lit
                let shape = WheelSegment(index: index, count: Self.sliceCount)
                shape
                    .fill(lit ? AnyShapeStyle(OrangeTheme.accentGradient) : AnyShapeStyle(latest ? OrangeTheme.accent : restFill))
                    .overlay(shape.stroke(Color.white.opacity(scheme == .dark ? 0.08 : 0.35), lineWidth: 1))
                    .frame(width: WheelMetrics.size, height: WheelMetrics.size)
                    .scaleEffect(shown ? 1 : 0.42)
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.25).delay(lit ? Double(index) * 0.025 : 0), value: lit)
            }
            OrangeMark(side: 72)
                .shadow(color: OrangeTheme.accent.opacity(lit ? 0.45 : 0.18), radius: lit ? 26 : 12)
                .scaleEffect(revealed > 0 ? 1 : 0.6)
                .opacity(revealed > 0 ? 1 : 0)
        }
        .frame(width: WheelMetrics.size, height: WheelMetrics.size)
        .scaleEffect(exiting ? 2.4 : 1)
        .opacity(exiting ? 0 : 1)
        .blur(radius: exiting ? 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Reports the window hosting this view once AppKit has attached it.
private struct WindowReader: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { onResolve(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let window = nsView?.window { onResolve(window) }
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

/// Opens the Settings window. It stays at the bottom of the sidebar, separate from the section selection.
private struct SettingsSidebarButton: View {
    @Environment(\.openSettings) private var openSettings
    @State private var hovered = false

    var body: some View {
        Button {
            openSettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(OrangeTheme.accent)
                    .frame(width: 20)
                Text(L("Settings", "Ayarlar"))
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.primary)
            .background {
                if hovered {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .help("\(L("Settings", "Ayarlar")) (⌘\(AppDelegate.settingsKey))")
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
