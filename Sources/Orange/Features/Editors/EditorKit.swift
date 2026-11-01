import AppKit
import OrangeKit
import SwiftUI

// MARK: Scaffold

struct EditorScaffold<Stage: View, Inspector: View, Footer: View>: View {
    @Environment(\.editor) private var editor
    var primaryTitle: String
    var canApply: Bool
    var busy: Bool
    var apply: () -> Void
    var stage: Stage
    var inspector: Inspector
    var footer: Footer

    init(
        primaryTitle: String = L("Apply", "Uygula"),
        canApply: Bool = true,
        busy: Bool = false,
        apply: @escaping () -> Void,
        @ViewBuilder stage: () -> Stage,
        @ViewBuilder inspector: () -> Inspector,
        @ViewBuilder footer: () -> Footer
    ) {
        self.primaryTitle = primaryTitle
        self.canApply = canApply
        self.busy = busy
        self.apply = apply
        self.stage = stage()
        self.inspector = inspector()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            HStack(spacing: 14) {
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OrangeTheme.stage)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        inspector
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .frame(width: 300)
                .glassCard(radius: 22)
            }
            HStack(spacing: 10) {
                footer
                Spacer()
                if busy {
                    ProgressView().controlSize(.small)
                }
                Button(L("Cancel", "Vazgeç")) { editor.close() }
                    .buttonStyle(.glass).tint(nil)
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: apply)
                    .buttonStyle(.glassProminent)
                    .tint(OrangeTheme.accent)
                    .disabled(!canApply || busy)
            }
            .controlSize(.large)
        }
        .background(EditorKeyMonitor(enabled: canApply && !busy, onReturn: apply, onEscape: editor.close))
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .padding(.top, 8)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: editor.tool.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(editor.tool.windowTitle).font(.system(size: 15, weight: .semibold))
                Text(editor.files.count == 1 ? editor.files[0].lastPathComponent : L("\(editor.files.count) files", "\(editor.files.count) dosya"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.leading, 72)
        .frame(height: 30)
    }
}

extension EditorScaffold where Footer == EmptyView {
    init(
        primaryTitle: String = L("Apply", "Uygula"),
        canApply: Bool = true,
        busy: Bool = false,
        apply: @escaping () -> Void,
        @ViewBuilder stage: () -> Stage,
        @ViewBuilder inspector: () -> Inspector
    ) {
        self.init(primaryTitle: primaryTitle, canApply: canApply, busy: busy, apply: apply, stage: stage, inspector: inspector) { EmptyView() }
    }
}

/// Return applies and Escape cancels, including when a glass button does not become the window’s default button.
private struct EditorKeyMonitor: NSViewRepresentable {
    var enabled: Bool
    var onReturn: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.enabled = enabled
        view.onReturn = onReturn
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.enabled = enabled
        view.onReturn = onReturn
        view.onEscape = onEscape
        view.installIfNeeded()
    }

    final class MonitorView: NSView {
        var enabled = false
        var onReturn: () -> Void = {}
        var onEscape: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installIfNeeded()
        }

        func installIfNeeded() {
            guard window != nil, monitor == nil else {
                if window == nil, let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                if event.window?.firstResponder is NSText { return event }
                let chars = event.charactersIgnoringModifiers ?? ""
                let isReturn = event.keyCode == 36 || event.keyCode == 76 || chars == "\r" || chars == "\u{3}"
                let isEscape = event.keyCode == 53 || chars == "\u{1b}"
                if isReturn {
                    guard self.enabled else { return event }
                    let action = self.onReturn
                    DispatchQueue.main.async(execute: action)
                    return nil
                }
                if isEscape {
                    let action = self.onEscape
                    DispatchQueue.main.async(execute: action)
                    return nil
                }
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

struct InspectorSection<Content: View>: View {
    var title: String
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: title, symbol: symbol)
            content
        }
    }
}

struct AdjustRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var defaultValue: Double = 0
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(format(value))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.snappy) { value = defaultValue }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(value == defaultValue ? Color.secondary.opacity(0.35) : OrangeTheme.accent)
                .disabled(value == defaultValue)
                .help(L("Reset", "Sıfırla"))
            }
            Slider(value: $value, in: range)
                .tint(OrangeTheme.accent)
                .controlSize(.small)
        }
    }
}

struct InfoRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.system(size: 12.5))
    }
}

struct ChoiceGrid<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value
    var columns = 3

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(options, id: \.0) { option in
                let selected = option.0 == selection
                Button {
                    withAnimation(.snappy) { selection = option.0 }
                } label: {
                    Text(option.1)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .glassEffect(selected ? .regular.tint(OrangeTheme.accent).interactive() : .regular.interactive(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

struct StageMessage: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.black.opacity(0.3)), in: Capsule())
    }
}

// MARK: Stages

/// Places content at its aspect-fit rect and hands that rect to overlays.
struct FittedStage<Content: View, Overlay: View>: View {
    var contentSize: CGSize
    var inset: CGFloat = 26
    @ViewBuilder var content: Content
    var overlay: (CGRect) -> Overlay

    var body: some View {
        GeometryReader { geometry in
            let area = CGSize(width: max(1, geometry.size.width - inset * 2), height: max(1, geometry.size.height - inset * 2))
            let fitted = CropMath.fittedRect(imageSize: contentSize, in: area).offsetBy(dx: inset, dy: inset)
            ZStack(alignment: .topLeading) {
                content
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
                overlay(fitted)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct ImageStage<Overlay: View>: View {
    var image: CGImage?
    var checkerboard = false
    var overlay: (CGRect) -> Overlay

    init(image: CGImage?, checkerboard: Bool = false, @ViewBuilder overlay: @escaping (CGRect) -> Overlay) {
        self.image = image
        self.checkerboard = checkerboard
        self.overlay = overlay
    }

    var body: some View {
        if let image {
            FittedStage(contentSize: CGSize(width: image.width, height: image.height)) {
                ZStack {
                    if checkerboard { Checkerboard() }
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                }
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            } overlay: { fitted in
                overlay(fitted)
            }
        } else {
            ProgressView().controlSize(.large).tint(.white)
        }
    }
}

extension ImageStage where Overlay == EmptyView {
    init(image: CGImage?, checkerboard: Bool = false) {
        self.init(image: image, checkerboard: checkerboard) { _ in EmptyView() }
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            for row in 0..<Int(ceil(size.height / cell)) {
                for column in 0..<Int(ceil(size.width / cell)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(.white.opacity(0.12)))
                }
            }
        }
        .background(Color.white.opacity(0.05))
    }
}

// MARK: Crop selector

struct CropSelector: View {
    /// Normalized, top-left origin.
    @Binding var rect: CGRect
    var fitted: CGRect
    var aspect: CGFloat?
    @State var start: CGRect?

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    private var viewRect: CGRect {
        CGRect(
            x: fitted.minX + rect.minX * fitted.width,
            y: fitted.minY + rect.minY * fitted.height,
            width: rect.width * fitted.width,
            height: rect.height * fitted.height
        )
    }

    var body: some View {
        let frame = viewRect
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(fitted)
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Path { path in
                for step in 1...2 {
                    let x = frame.minX + frame.width * CGFloat(step) / 3
                    let y = frame.minY + frame.height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: frame.minY))
                    path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    path.move(to: CGPoint(x: frame.minX, y: y))
                    path.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 0.8)
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(.white, lineWidth: 1.5)
                .contentShape(Rectangle())
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .gesture(moveGesture)

            ForEach(Corner.allCases, id: \.self) { corner in
                let point = position(of: corner, in: frame)
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .position(point)
                    .gesture(resizeGesture(corner))
            }
        }
    }

    private func position(of corner: Corner, in frame: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: frame.minX, y: frame.minY)
        case .topRight: CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft: CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight: CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let base = start ?? viewRect
                if start == nil { start = base }
                var moved = base.offsetBy(dx: value.translation.width, dy: value.translation.height)
                moved.origin.x = min(max(moved.minX, fitted.minX), fitted.maxX - moved.width)
                moved.origin.y = min(max(moved.minY, fitted.minY), fitted.maxY - moved.height)
                rect = normalize(moved)
            }
            .onEnded { _ in start = nil }
    }

    private func resizeGesture(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let base = start ?? viewRect
                if start == nil { start = base }
                let anchor: CGPoint
                var moving: CGPoint
                switch corner {
                case .topLeft:
                    anchor = CGPoint(x: base.maxX, y: base.maxY)
                    moving = CGPoint(x: base.minX, y: base.minY)
                case .topRight:
                    anchor = CGPoint(x: base.minX, y: base.maxY)
                    moving = CGPoint(x: base.maxX, y: base.minY)
                case .bottomLeft:
                    anchor = CGPoint(x: base.maxX, y: base.minY)
                    moving = CGPoint(x: base.minX, y: base.maxY)
                case .bottomRight:
                    anchor = CGPoint(x: base.minX, y: base.minY)
                    moving = CGPoint(x: base.maxX, y: base.maxY)
                }
                moving.x = min(max(moving.x + value.translation.width, fitted.minX), fitted.maxX)
                moving.y = min(max(moving.y + value.translation.height, fitted.minY), fitted.maxY)
                var width = max(24, abs(moving.x - anchor.x))
                var height = max(24, abs(moving.y - anchor.y))
                let signX: CGFloat = moving.x < anchor.x ? -1 : 1
                let signY: CGFloat = moving.y < anchor.y ? -1 : 1
                if let aspect {
                    height = width / aspect
                    let limitY = signY < 0 ? anchor.y - fitted.minY : fitted.maxY - anchor.y
                    if height > limitY {
                        height = limitY
                        width = height * aspect
                    }
                }
                let limitX = signX < 0 ? anchor.x - fitted.minX : fitted.maxX - anchor.x
                width = min(width, limitX)
                let x = signX < 0 ? anchor.x - width : anchor.x
                let y = signY < 0 ? anchor.y - height : anchor.y
                rect = normalize(CGRect(x: x, y: y, width: width, height: height))
            }
            .onEnded { _ in start = nil }
    }

    private func normalize(_ frame: CGRect) -> CGRect {
        CGRect(
            x: (frame.minX - fitted.minX) / fitted.width,
            y: (frame.minY - fitted.minY) / fitted.height,
            width: frame.width / fitted.width,
            height: frame.height / fitted.height
        )
    }

    /// Largest centered rect of the given pixel aspect inside an image.
    static func centered(aspect: CGFloat?, imageSize: CGSize) -> CGRect {
        guard let aspect, imageSize.width > 0, imageSize.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let imageAspect = imageSize.width / imageSize.height
        if aspect > imageAspect {
            let height = imageAspect / aspect
            return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
        let width = aspect / imageAspect
        return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
    }
}

// MARK: Region drawer

struct RegionDrawer: View {
    @Binding var regions: [CGRect]
    var fitted: CGRect
    @State var draft: CGRect?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: fitted.width, height: fitted.height)
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .local)
                        .onChanged { value in
                            draft = CGRect(
                                x: min(value.startLocation.x, value.location.x),
                                y: min(value.startLocation.y, value.location.y),
                                width: abs(value.location.x - value.startLocation.x),
                                height: abs(value.location.y - value.startLocation.y)
                            ).intersection(CGRect(origin: .zero, size: fitted.size))
                        }
                        .onEnded { _ in
                            if let draft, draft.width > 6, draft.height > 6 {
                                regions.append(CGRect(
                                    x: draft.minX / fitted.width,
                                    y: draft.minY / fitted.height,
                                    width: draft.width / fitted.width,
                                    height: draft.height / fitted.height
                                ))
                            }
                            draft = nil
                        }
                )
                .position(x: fitted.midX, y: fitted.midY)

            ForEach(Array(regions.enumerated()), id: \.offset) { index, region in
                let frame = CGRect(
                    x: fitted.minX + region.minX * fitted.width,
                    y: fitted.minY + region.minY * fitted.height,
                    width: region.width * fitted.width,
                    height: region.height * fitted.height
                )
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(OrangeTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                    .frame(width: frame.width, height: frame.height)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            regions.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white, OrangeTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 8, y: -8)
                    }
                    .position(x: frame.midX, y: frame.midY)
            }

            if let draft {
                RoundedRectangle(cornerRadius: 4)
                    .fill(OrangeTheme.accent.opacity(0.2))
                    .strokeBorder(OrangeTheme.accent, lineWidth: 2)
                    .frame(width: draft.width, height: draft.height)
                    .position(x: fitted.minX + draft.midX, y: fitted.minY + draft.midY)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: Helpers

extension View {
    /// Re-runs an async render whenever `value` changes, debounced.
    func debouncedTask<V: Equatable>(_ value: V, delay: Duration = .milliseconds(60), _ action: @escaping @Sendable () async -> Void) -> some View {
        task(id: value) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

func formatSeconds(_ seconds: Double) -> String {
    Timecode.string(seconds, fraction: true)
}

func fileSize(_ url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
}
