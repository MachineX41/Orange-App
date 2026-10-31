import AppKit
import OrangeKit
import SwiftUI

// MARK: Edit Photo

struct AdjustEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var source: CGImage?
    @State var preview: CGImage?
    @State var values = PhotoAdjustments()
    @State var showOriginal = false

    var body: some View {
        EditorScaffold(primaryTitle: L("Save Copy", "Kopyayı Kaydet"), canApply: !values.isIdentity, apply: apply) {
            ImageStage(image: showOriginal ? source : (preview ?? source))
                .overlay(alignment: .top) {
                    if showOriginal { StageMessage(text: L("Original", "Orijinal")).padding(.top, 12) }
                }
        } inspector: {
            InspectorSection(title: L("Light", "Işık"), symbol: "sun.max") {
                AdjustRow(title: L("Exposure", "Pozlama"), value: $values.exposure, range: -3...3) { String(format: "%.2f EV", $0) }
                AdjustRow(title: L("Brightness", "Parlaklık"), value: $values.brightness, range: -100...100)
                AdjustRow(title: L("Contrast", "Kontrast"), value: $values.contrast, range: -100...100)
                AdjustRow(title: L("Highlights", "Açık Tonlar"), value: $values.highlights, range: -100...100)
                AdjustRow(title: L("Shadows", "Gölgeler"), value: $values.shadows, range: -100...100)
            }
            InspectorSection(title: L("Color", "Renk"), symbol: "paintpalette") {
                AdjustRow(title: L("Saturation", "Doygunluk"), value: $values.saturation, range: -100...100)
                AdjustRow(title: L("Vibrance", "Canlılık"), value: $values.vibrance, range: -100...100)
                AdjustRow(title: L("Warmth", "Sıcaklık"), value: $values.warmth, range: -100...100)
                AdjustRow(title: L("Tint", "Ton"), value: $values.tint, range: -100...100)
            }
            InspectorSection(title: L("Detail", "Detay"), symbol: "circle.dotted") {
                AdjustRow(title: L("Sharpness", "Keskinlik"), value: $values.sharpness, range: 0...100)
                AdjustRow(title: L("Vignette", "Vinyet"), value: $values.vignette, range: 0...100)
            }
        } footer: {
            Button {
                showOriginal.toggle()
            } label: {
                Label(L("Compare", "Karşılaştır"), systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(.glass).tint(nil)
            .keyboardShortcut("m", modifiers: [])
            Button(L("Reset All", "Tümünü Sıfırla")) {
                withAnimation { values = PhotoAdjustments() }
            }
            .buttonStyle(.glass).tint(nil)
            .disabled(values.isIdentity)
        }
        .task { source = await PreviewLoader.image(url, maxPixel: 1800) }
        .task(id: values) {
            guard let source else { return }
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            let current = values
            let rendered = await Task.detached(priority: .userInitiated) { try? PhotoAdjust.render(current, image: source) }.value
            if !Task.isCancelled { preview = rendered }
        }
    }

    private func apply() {
        let current = values
        let url = url
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            let output = try PhotoAdjust.render(current, image: ImageEngine.load(url))
            return [try ImageEngine.save(output, from: url, suffix: L("Edited", "Düzenlenmiş"), keepMetadata: true)]
        }
        editor.close()
    }
}

// MARK: Add background

struct BackdropEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var source: CGImage?
    @State var preview: CGImage?
    @State var style = BackdropStyle()

    static let gradients: [[RGBA]] = [
        [RGBA(hex: 0xFFC46B), RGBA(hex: 0xF0522B)],
        [RGBA(hex: 0xFF9A9E), RGBA(hex: 0xFAD0C4)],
        [RGBA(hex: 0xA18CD1), RGBA(hex: 0xFBC2EB)],
        [RGBA(hex: 0xF6D365), RGBA(hex: 0xFDA085)],
        [RGBA(hex: 0x84FAB0), RGBA(hex: 0x8FD3F4)],
        [RGBA(hex: 0x667EEA), RGBA(hex: 0x764BA2)],
        [RGBA(hex: 0xFF5F6D), RGBA(hex: 0xFFC371)],
        [RGBA(hex: 0x30CFD0), RGBA(hex: 0x330867)],
        [RGBA(hex: 0x43E97B), RGBA(hex: 0x38F9D7)],
        [RGBA(hex: 0xFA709A), RGBA(hex: 0xFEE140)],
        [RGBA(hex: 0x0F2027), RGBA(hex: 0x2C5364)],
        [RGBA(hex: 0xE0C3FC), RGBA(hex: 0x8EC5FC)]
    ]
    static let solids: [RGBA] = [
        RGBA(1, 1, 1), RGBA(hex: 0xF2F2F7), RGBA(hex: 0x1C1C1E), RGBA(0, 0, 0),
        RGBA(hex: 0xFF6B35), RGBA(hex: 0xFFD60A), RGBA(hex: 0x34C759), RGBA(hex: 0x0A84FF),
        RGBA(hex: 0x5E5CE6), RGBA(hex: 0xFF375F), RGBA(hex: 0xC7A27C), RGBA(hex: 0x8E8E93)
    ]

    var body: some View {
        EditorScaffold(primaryTitle: L("Save Copy", "Kopyayı Kaydet"), apply: apply) {
            ImageStage(image: preview ?? source)
        } inspector: {
            InspectorSection(title: L("Background", "Arka Plan"), symbol: "paintbrush") {
                swatches
                Button {
                    Task {
                        let urls = await runtime.chooseFiles(kinds: [.image], multiple: false)
                        if let path = urls.first?.path { style.fill = .image(path) }
                    }
                } label: {
                    Label(L("Use an Image…", "Görsel Kullan…"), systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).tint(nil)
            }
            InspectorSection(title: L("Frame", "Çerçeve"), symbol: "square.dashed") {
                AdjustRow(title: L("Padding", "Boşluk"), value: $style.padding, range: 0...0.4, defaultValue: 0.12) { "\(Int($0 * 100))%" }
                AdjustRow(title: L("Corner Radius", "Köşe"), value: $style.cornerRadius, range: 0...0.2, defaultValue: 0.04) { "\(Int($0 * 500))" }
                AdjustRow(title: L("Shadow", "Gölge"), value: $style.shadow, range: 0...1, defaultValue: 0.5) { "\(Int($0 * 100))%" }
            }
            InspectorSection(title: L("Canvas", "Tuval"), symbol: "aspectratio") {
                ChoiceGrid(options: [
                    (BackdropStyle.Aspect.auto, L("Auto", "Oto")),
                    (.square, "1:1"),
                    (.landscape, "16:9"),
                    (.portrait, "4:5"),
                    (.story, "9:16")
                ], selection: $style.aspect)
            }
        }
        .task { source = await PreviewLoader.image(url, maxPixel: 1200) }
        .task(id: [AnyHashable(style), AnyHashable(source == nil)]) {
            guard let source else { return }
            let current = style
            let rendered = await Task.detached(priority: .userInitiated) { try? Backdrop.render(source, style: current) }.value
            if !Task.isCancelled { preview = rendered }
        }
    }

    private var swatches: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(Array(Self.gradients.enumerated()), id: \.offset) { _, colors in
                swatch(.gradient(colors)) {
                    LinearGradient(colors: colors.map { Color($0) }, startPoint: .bottomLeading, endPoint: .topTrailing)
                }
            }
            ForEach(Array(Self.solids.enumerated()), id: \.offset) { _, color in
                swatch(.solid(color)) { Color(color) }
            }
        }
    }

    private func swatch<Fill: View>(_ fill: BackdropFill, @ViewBuilder content: () -> Fill) -> some View {
        let selected = style.fill == fill
        return Button {
            withAnimation(.snappy) { style.fill = fill }
        } label: {
            content()
                .frame(height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? OrangeTheme.accent : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func apply() {
        let current = style
        let url = url
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            let output = try Backdrop.render(ImageEngine.load(url, maxPixel: 6000), style: current)
            return [try ImageEngine.save(output, from: url, suffix: L("Background", "Arka Plan"), format: .png)]
        }
        editor.close()
    }
}

// MARK: Annotate

struct AnnotateEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var source: CGImage?
    @State var marks: [Mark] = []
    @State var draft: Mark?
    @State var tool: MarkTool = .arrow
    @State var color = RGBA(hex: 0xFF3B30)
    @State var width = 0.008
    @State var text = L("Text", "Metin")

    static let palette: [RGBA] = [
        RGBA(hex: 0xFF3B30), RGBA(hex: 0xFF9500), RGBA(hex: 0xFFCC00), RGBA(hex: 0x34C759),
        RGBA(hex: 0x0A84FF), RGBA(hex: 0xAF52DE), RGBA(1, 1, 1), RGBA(0, 0, 0)
    ]

    var body: some View {
        EditorScaffold(primaryTitle: L("Save Copy", "Kopyayı Kaydet"), canApply: !marks.isEmpty, apply: apply) {
            ImageStage(image: source) { fitted in
                Canvas { context, size in
                    context.withCGContext { cg in
                        for mark in marks + (draft.map { [$0] } ?? []) {
                            AnnotationRenderer.draw(mark, in: cg, size: size)
                        }
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .contentShape(Rectangle())
                .gesture(drawGesture(size: fitted.size))
                .position(x: fitted.midX, y: fitted.midY)
            }
        } inspector: {
            InspectorSection(title: L("Tool", "Araç"), symbol: "pencil.and.scribble") {
                ChoiceGrid(options: [
                    (MarkTool.pen, L("Pen", "Kalem")),
                    (.highlighter, L("Marker", "Fosforlu")),
                    (.arrow, L("Arrow", "Ok")),
                    (.rectangle, L("Box", "Kutu")),
                    (.ellipse, L("Oval", "Oval")),
                    (.text, L("Text", "Metin"))
                ], selection: $tool)
                if tool == .text {
                    TextField(L("Text to place", "Yerleştirilecek metin"), text: $text)
                        .textFieldStyle(.roundedBorder)
                }
            }
            InspectorSection(title: L("Color", "Renk"), symbol: "paintpalette") {
                HStack(spacing: 8) {
                    ForEach(Array(Self.palette.enumerated()), id: \.offset) { _, swatch in
                        Button {
                            color = swatch
                        } label: {
                            Circle()
                                .fill(Color(swatch))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                                .overlay(Circle().strokeBorder(OrangeTheme.accent, lineWidth: color == swatch ? 2.5 : 0).padding(-4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                AdjustRow(title: L("Size", "Boyut"), value: $width, range: 0.002...0.03, defaultValue: 0.008) { "\(Int($0 * 1000))" }
            }
            InspectorSection(title: L("Marks", "İşaretler"), symbol: "list.bullet") {
                HStack {
                    Button(L("Undo", "Geri Al")) { _ = marks.popLast() }
                        .keyboardShortcut("z")
                        .disabled(marks.isEmpty)
                    Button(L("Clear", "Temizle")) { marks.removeAll() }
                        .disabled(marks.isEmpty)
                }
                .buttonStyle(.glass).tint(nil)
                Text(L("\(marks.count) mark(s)", "\(marks.count) işaret"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task { source = await PreviewLoader.image(url, maxPixel: 2000) }
    }

    private func drawGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: min(max(value.location.x / size.width, 0), 1), y: min(max(value.location.y / size.height, 0), 1))
                if draft == nil {
                    let start = CGPoint(x: value.startLocation.x / size.width, y: value.startLocation.y / size.height)
                    draft = Mark(tool: tool, points: [start], color: color, width: width, text: tool == .text ? text : "")
                }
                switch tool {
                case .pen, .highlighter:
                    draft?.points.append(point)
                case .text:
                    draft?.points = [point]
                default:
                    if let first = draft?.points.first { draft?.points = [first, point] }
                }
            }
            .onEnded { _ in
                if var mark = draft {
                    if mark.points.count == 1, mark.tool != .text { mark.points.append(mark.points[0]) }
                    marks.append(mark)
                }
                draft = nil
            }
    }

    private func apply() {
        let current = marks
        let url = url
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            let output = try AnnotationRenderer.render(current, onto: ImageEngine.load(url))
            return [try ImageEngine.save(output, from: url, suffix: L("Annotated", "İşaretli"))]
        }
        editor.close()
    }
}

// MARK: Redact

struct RedactImageEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var source: CGImage?
    @State var preview: CGImage?
    @State var regions: [CGRect] = []
    @State var style: RedactStyle = .pixelate
    @State var finding = false

    var body: some View {
        EditorScaffold(primaryTitle: L("Save Copy", "Kopyayı Kaydet"), canApply: !regions.isEmpty, busy: finding, apply: apply) {
            ImageStage(image: preview ?? source) { fitted in
                RegionDrawer(regions: $regions, fitted: fitted)
            }
            .overlay(alignment: .bottom) {
                if regions.isEmpty {
                    StageMessage(text: L("Drag over anything you want to hide", "Gizlemek istediğiniz alanın üzerinde sürükleyin")).padding(.bottom, 14)
                }
            }
        } inspector: {
            InspectorSection(title: L("Style", "Stil"), symbol: "eye.slash") {
                ChoiceGrid(options: [
                    (RedactStyle.pixelate, L("Pixelate", "Pikselle")),
                    (.blur, L("Blur", "Bulanık")),
                    (.solid, L("Block", "Blok"))
                ], selection: $style)
            }
            InspectorSection(title: L("Find Automatically", "Otomatik Bul"), symbol: "sparkle.magnifyingglass") {
                Button { find(faces: true) } label: {
                    Label(L("Faces", "Yüzler"), systemImage: "face.smiling").frame(maxWidth: .infinity)
                }
                Button { find(faces: false) } label: {
                    Label(L("Text", "Metin"), systemImage: "text.viewfinder").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass).tint(nil)
            InspectorSection(title: L("Regions", "Bölgeler"), symbol: "square.dashed") {
                Text(L("\(regions.count) region(s)", "\(regions.count) bölge"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(L("Remove All", "Tümünü Kaldır")) { regions.removeAll() }
                    .buttonStyle(.glass).tint(nil)
                    .disabled(regions.isEmpty)
            }
        }
        .task { source = await PreviewLoader.image(url, maxPixel: 1800) }
        .task(id: RedactKey(regions: regions, style: style, ready: source != nil)) {
            guard let source else { return }
            let current = regions
            let style = style
            let rendered = await Task.detached(priority: .userInitiated) { try? Redactor.render(current, style: style, image: source) }.value
            if !Task.isCancelled { preview = rendered }
        }
    }

    private func find(faces: Bool) {
        guard let source else { return }
        finding = true
        Task {
            let found = await Task.detached {
                (try? (faces ? RegionFinder.faces(in: source) : RegionFinder.text(in: source))) ?? []
            }.value
            finding = false
            if found.isEmpty {
                runtime.toast(editor.tool.title, OrangeError.nothingFound.message, symbol: "magnifyingglass", style: .info)
            }
            regions += found
        }
    }

    private func apply() {
        let current = regions
        let style = style
        let url = url
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            let output = try Redactor.render(current, style: style, image: ImageEngine.load(url))
            return [try ImageEngine.save(output, from: url, suffix: L("Redacted", "Gizlenmiş"))]
        }
        editor.close()
    }
}

struct RedactKey: Hashable {
    var regions: [CGRect]
    var style: RedactStyle
    var ready: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(regions.count)
        hasher.combine(style)
        hasher.combine(ready)
        for region in regions {
            hasher.combine(region.minX)
            hasher.combine(region.minY)
            hasher.combine(region.width)
        }
    }
}

// MARK: Crop & rotate

enum CropAspect: String, CaseIterable, Hashable {
    case free, original, square, fourThree, threeTwo, sixteenNine, nineSixteen

    var title: String {
        switch self {
        case .free: L("Free", "Serbest")
        case .original: L("Original", "Orijinal")
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        case .nineSixteen: "9:16"
        }
    }

    func ratio(for size: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: size.height > 0 ? size.width / size.height : nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .threeTwo: 3.0 / 2.0
        case .sixteenNine: 16.0 / 9.0
        case .nineSixteen: 9.0 / 16.0
        }
    }
}

struct CropEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var source: CGImage?
    @State var shown: CGImage?
    @State var turns = 0
    @State var flipH = false
    @State var flipV = false
    @State var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State var aspect: CropAspect = .free

    private var shownSize: CGSize { shown.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
    private var changed: Bool { turns != 0 || flipH || flipV || rect != CGRect(x: 0, y: 0, width: 1, height: 1) }

    var body: some View {
        EditorScaffold(primaryTitle: L("Save Copy", "Kopyayı Kaydet"), canApply: changed, apply: apply) {
            ImageStage(image: shown) { fitted in
                CropSelector(rect: $rect, fitted: fitted, aspect: aspect.ratio(for: shownSize))
            }
        } inspector: {
            InspectorSection(title: L("Aspect Ratio", "En Boy Oranı"), symbol: "aspectratio") {
                ChoiceGrid(options: CropAspect.allCases.map { ($0, $0.title) }, selection: $aspect)
            }
            InspectorSection(title: L("Rotate & Flip", "Döndür ve Çevir"), symbol: "rotate.right") {
                HStack(spacing: 8) {
                    tile("rotate.left", L("Left", "Sola")) { turns = (turns + 3) % 4 }
                    tile("rotate.right", L("Right", "Sağa")) { turns = (turns + 1) % 4 }
                    tile("arrow.left.and.right.righttriangle.left.righttriangle.right", L("Flip H", "Yatay")) { flipH.toggle() }
                    tile("arrow.up.and.down.righttriangle.up.righttriangle.down", L("Flip V", "Dikey")) { flipV.toggle() }
                }
            }
            InspectorSection(title: L("Output", "Çıktı"), symbol: "info.circle") {
                let width = Int((rect.width * shownSize.width / max(previewScale, 0.0001)).rounded())
                let height = Int((rect.height * shownSize.height / max(previewScale, 0.0001)).rounded())
                InfoRow(title: L("Size", "Boyut"), value: "\(width) × \(height) px")
                Button(L("Reset", "Sıfırla")) {
                    turns = 0; flipH = false; flipV = false; aspect = .free
                    rect = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
                .buttonStyle(.glass).tint(nil)
            }
        }
        .task { source = await PreviewLoader.image(url, maxPixel: 1800) }
        .task(id: [turns, flipH ? 1 : 0, flipV ? 1 : 0, source == nil ? 0 : 1]) {
            guard let source else { return }
            let turns = turns, flipH = flipH, flipV = flipV
            shown = await Task.detached { try? Self.orient(source, turns: turns, flipH: flipH, flipV: flipV) }.value
            rect = CropSelector.centered(aspect: aspect.ratio(for: shownSize), imageSize: shownSize)
        }
        .onChange(of: aspect) { _, value in
            withAnimation(.snappy) { rect = CropSelector.centered(aspect: value.ratio(for: shownSize), imageSize: shownSize) }
        }
    }

    private var previewScale: CGFloat {
        let original = ImageEngine.pixelSize(of: url)
        guard let source, original.width > 0 else { return 1 }
        return CGFloat(source.width) / original.width
    }

    private func tile(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    nonisolated static func orient(_ image: CGImage, turns: Int, flipH: Bool, flipV: Bool) throws -> CGImage {
        var output = try ImageEngine.transform(image, .rotateClockwise(turns * 90))
        if flipH { output = try ImageEngine.transform(output, .flipHorizontal) }
        if flipV { output = try ImageEngine.transform(output, .flipVertical) }
        return output
    }

    private func apply() {
        let turns = turns, flipH = flipH, flipV = flipV, rect = rect
        let url = url
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            var image = try Self.orient(ImageEngine.load(url), turns: turns, flipH: flipH, flipV: flipV)
            if rect != CGRect(x: 0, y: 0, width: 1, height: 1) {
                image = try ImageEngine.transform(image, .cropNormalized(rect))
            }
            return [try ImageEngine.save(image, from: url, suffix: L("Cropped", "Kırpılmış"), keepMetadata: true)]
        }
        editor.close()
    }
}

// MARK: Resize

struct ResizeEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var source: CGImage?
    @State var original = CGSize.zero
    @State var width = 0
    @State var height = 0
    @State var locked = true
    @State var format: ConvertTarget = .png

    var body: some View {
        EditorScaffold(primaryTitle: L("Resize", "Boyutlandır"), canApply: width > 0 && height > 0 && (width != Int(original.width) || height != Int(original.height) || format != ImageEngine.sameFormat(as: url)), apply: apply) {
            ImageStage(image: source)
                .overlay(alignment: .bottom) {
                    StageMessage(text: "\(Int(original.width)) × \(Int(original.height))  →  \(width) × \(height) px").padding(.bottom, 14)
                }
        } inspector: {
            InspectorSection(title: L("Dimensions", "Boyutlar"), symbol: "ruler") {
                HStack(spacing: 8) {
                    field(L("Width", "Genişlik"), value: Binding(get: { width }, set: { setWidth($0) }))
                    Button {
                        locked.toggle()
                        if locked { setWidth(width) }
                    } label: {
                        Image(systemName: locked ? "lock.fill" : "lock.open")
                    }
                    .buttonStyle(.glass).tint(nil)
                    .buttonBorderShape(.circle)
                    .padding(.top, 16)
                    field(L("Height", "Yükseklik"), value: Binding(get: { height }, set: { setHeight($0) }))
                }
                ChoiceGrid(options: [(25, "25%"), (50, "50%"), (75, "75%"), (100, "100%"), (150, "150%"), (200, "200%")], selection: Binding(
                    get: { original.width > 0 ? Int((Double(width) / original.width * 100).rounded()) : 100 },
                    set: { percent in
                        width = Int((original.width * Double(percent) / 100).rounded())
                        height = Int((original.height * Double(percent) / 100).rounded())
                    }
                ))
            }
            InspectorSection(title: L("Format", "Biçim"), symbol: "photo") {
                ChoiceGrid(options: ([.png, .jpeg, .heic, .webp, .tiff] as [ConvertTarget]).filter(ImageCapabilities.canWrite).map { ($0, $0.title) }, selection: $format)
            }
        }
        .task {
            original = ImageEngine.pixelSize(of: url)
            width = Int(original.width)
            height = Int(original.height)
            format = ImageEngine.sameFormat(as: url)
            source = await PreviewLoader.image(url, maxPixel: 1600)
        }
    }

    private func field(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
        }
    }

    private func setWidth(_ value: Int) {
        width = max(1, min(value, 20000))
        if locked, original.width > 0 { height = max(1, Int((Double(width) * original.height / original.width).rounded())) }
    }

    private func setHeight(_ value: Int) {
        height = max(1, min(value, 20000))
        if locked, original.height > 0 { width = max(1, Int((Double(height) * original.width / original.height).rounded())) }
    }

    private func apply() {
        let width = width, height = height, format = format, url = url
        let quality = runtime.imageQuality
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            let image = try ImageEngine.transform(ImageEngine.load(url), .resize(width: width, height: height))
            return [try ImageEngine.save(image, from: url, suffix: "\(width)×\(height)", format: format, quality: quality, keepMetadata: true)]
        }
        editor.close()
    }
}

// MARK: Compress images

struct CompressImagesEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var urls: [URL]
    @State var source: CGImage?
    @State var quality = 0.75
    @State var format: ConvertTarget = .jpeg
    @State var maxSide = 0
    @State var keepMetadata = false
    @State var estimate: Int64?

    private var formats: [ConvertTarget] {
        ([.jpeg, .heic, .webp, .avif] as [ConvertTarget]).filter(ImageCapabilities.canWrite)
    }

    var body: some View {
        EditorScaffold(primaryTitle: urls.count > 1 ? L("Compress \(urls.count) Images", "\(urls.count) Görseli Sıkıştır") : L("Compress", "Sıkıştır"), apply: apply) {
            ImageStage(image: source)
                .overlay(alignment: .bottom) {
                    if let first = urls.first {
                        let before = fileSize(first)
                        HStack(spacing: 8) {
                            Text(ByteCountFormatter.string(fromByteCount: before, countStyle: .file))
                            Image(systemName: "arrow.right")
                            if let estimate {
                                Text(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)).bold()
                                if before > 0 {
                                    let change = Double(estimate - before) / Double(before)
                                    Text(change, format: .percent.precision(.fractionLength(0)))
                                        .foregroundStyle(change < 0 ? Color.green : OrangeTheme.ember)
                                }
                            } else {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .glassEffect(.regular.tint(.black.opacity(0.3)), in: Capsule())
                        .padding(.bottom, 14)
                    }
                }
        } inspector: {
            InspectorSection(title: L("Quality", "Kalite"), symbol: "dial.medium") {
                AdjustRow(title: L("Quality", "Kalite"), value: $quality, range: 0.1...1, defaultValue: 0.75) { "\(Int($0 * 100))%" }
            }
            InspectorSection(title: L("Format", "Biçim"), symbol: "photo") {
                ChoiceGrid(options: formats.map { ($0, $0.title) }, selection: $format, columns: 4)
            }
            InspectorSection(title: L("Longest Side", "Uzun Kenar"), symbol: "arrow.up.left.and.arrow.down.right") {
                ChoiceGrid(options: [(0, L("Original", "Orijinal")), (3840, "3840"), (2560, "2560"), (1920, "1920"), (1280, "1280"), (800, "800")], selection: $maxSide)
            }
            InspectorSection(title: L("Privacy", "Gizlilik"), symbol: "hand.raised") {
                Toggle(L("Keep metadata (EXIF, GPS)", "Meta veriyi koru (EXIF, GPS)"), isOn: $keepMetadata)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if urls.count > 1 {
                InspectorSection(title: L("Files", "Dosyalar"), symbol: "photo.stack") {
                    ForEach(urls, id: \.self) { url in
                        HStack {
                            FileThumbnail(url: url, side: 28, radius: 6)
                            Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: fileSize(url), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task {
            if let first = urls.first { source = await PreviewLoader.image(first, maxPixel: 1600) }
        }
        .task(id: [quality, Double(maxSide), Double(format.hashValue)]) {
            estimate = nil
            try? await Task.sleep(for: .milliseconds(120))
            guard let first = urls.first, !Task.isCancelled else { return }
            let quality = quality, format = format, maxSide = maxSide
            let size = await Task.detached(priority: .utility) { () -> Int64? in
                guard let image = try? ImageEngine.load(first, maxPixel: maxSide > 0 ? maxSide : nil),
                      let data = try? ImageEngine.encode(image, as: format, quality: quality) else { return nil }
                return Int64(data.count)
            }.value
            if !Task.isCancelled { estimate = size }
        }
        .onAppear {
            quality = runtime.imageQuality < 0.9 ? runtime.imageQuality : 0.75
            if !formats.contains(format) { format = formats.first ?? .jpeg }
        }
    }

    private func apply() {
        let quality = quality, format = format, maxSide = maxSide, keep = keepMetadata
        runtime.runEach(urls, title: editor.tool.windowTitle, symbol: editor.tool.symbol) { url, _ in
            let image = try ImageEngine.load(url, maxPixel: maxSide > 0 ? maxSide : nil)
            return [try ImageEngine.save(image, from: url, suffix: L("Compressed", "Sıkıştırılmış"), format: format, quality: quality, keepMetadata: keep)]
        }
        editor.close()
    }
}

// MARK: Collage

struct CollageEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    @State var urls: [URL]
    @State var images: [URL: CGImage] = [:]
    @State var preview: CGImage?
    @State var style = CollageStyle()

    init(urls: [URL]) {
        _urls = State(initialValue: urls)
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Create Collage", "Kolaj Oluştur"), canApply: urls.count >= 2, apply: apply) {
            ImageStage(image: preview)
        } inspector: {
            InspectorSection(title: L("Layout", "Yerleşim"), symbol: "square.grid.2x2") {
                ChoiceGrid(options: [(0, L("Auto", "Oto")), (1, "1"), (2, "2"), (3, "3"), (4, "4"), (5, "5")], selection: $style.columns)
                ChoiceGrid(options: [(1.0, "1:1"), (4.0 / 3.0, "4:3"), (3.0 / 4.0, "3:4"), (16.0 / 9.0, "16:9")], selection: $style.cellAspect, columns: 4)
                AdjustRow(title: L("Spacing", "Boşluk"), value: $style.spacing, range: 0...0.08, defaultValue: 0.02) { "\(Int($0 * 1000))" }
                AdjustRow(title: L("Corner Radius", "Köşe"), value: $style.cornerRadius, range: 0...0.3, defaultValue: 0.04) { "\(Int($0 * 100))" }
            }
            InspectorSection(title: L("Background", "Arka Plan"), symbol: "paintbrush") {
                HStack(spacing: 8) {
                    ForEach(Array([RGBA(1, 1, 1), RGBA(hex: 0xF2F2F7), RGBA(hex: 0x1C1C1E), RGBA(0, 0, 0), RGBA(hex: 0xFFE7C2), RGBA(hex: 0xF26B1D)].enumerated()), id: \.offset) { _, color in
                        Button { style.background = color } label: {
                            Circle().fill(Color(color)).frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                                .overlay(Circle().strokeBorder(OrangeTheme.accent, lineWidth: style.background == color ? 2.5 : 0).padding(-4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            InspectorSection(title: L("Order", "Sıra"), symbol: "arrow.up.arrow.down") {
                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                    HStack(spacing: 8) {
                        FileThumbnail(url: url, side: 30, radius: 6)
                        Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == urls.count - 1)
                        Button { urls.remove(at: index) } label: { Image(systemName: "minus.circle") }
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    Task { urls += await runtime.chooseFiles(kinds: [.image]) }
                } label: {
                    Label(L("Add Images…", "Görsel Ekle…"), systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).tint(nil)
            }
        }
        .task(id: urls) {
            for url in urls where images[url] == nil {
                images[url] = await PreviewLoader.image(url, maxPixel: 900)
            }
            await render()
        }
        .task(id: style) { await render() }
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard urls.indices.contains(target) else { return }
        withAnimation { urls.swapAt(index, target) }
    }

    private func render() async {
        let list = urls.compactMap { images[$0] }
        guard !list.isEmpty else { return }
        var small = style
        small.width = 1400
        preview = await Task.detached(priority: .userInitiated) { try? Collage.render(list, style: small) }.value
    }

    private func apply() {
        let urls = urls, style = style
        let quality = runtime.imageQuality
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: L("\(urls.count) images", "\(urls.count) görsel")) { _ in
            var full = style
            full.width = 3600
            let images = try urls.map { try ImageEngine.load($0, maxPixel: 2400) }
            let output = try Collage.render(images, style: full)
            return [try ImageEngine.save(output, from: urls[0], suffix: L("Collage", "Kolaj"), format: .jpeg, quality: max(quality, 0.9))]
        }
        editor.close()
    }
}
