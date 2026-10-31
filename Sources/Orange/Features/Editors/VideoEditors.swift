import AppKit
import OrangeKit
import SwiftUI

/// Video on top, filmstrip timeline below.
struct VideoTimelineStage<Overlay: View>: View {
    var url: URL
    var model: PlayerModel
    var size: CGSize
    var range: Binding<ClosedRange<Double>>?
    var markers: [Double] = []
    var overlay: (CGRect) -> Overlay

    init(url: URL, model: PlayerModel, size: CGSize, range: Binding<ClosedRange<Double>>? = nil, markers: [Double] = [], @ViewBuilder overlay: @escaping (CGRect) -> Overlay) {
        self.url = url
        self.model = model
        self.size = size
        self.range = range
        self.markers = markers
        self.overlay = overlay
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoStage(model: model, size: size, overlay: overlay)
            RangeTimeline(
                duration: max(model.duration, 0.01),
                range: range ?? .constant(0...max(model.duration, 0.01)),
                playhead: model.time,
                markers: markers,
                editable: range != nil,
                onSeek: { model.seek($0) }
            ) {
                ThumbnailStrip(url: url)
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }
}

extension VideoTimelineStage where Overlay == EmptyView {
    init(url: URL, model: PlayerModel, size: CGSize, range: Binding<ClosedRange<Double>>? = nil, markers: [Double] = []) {
        self.init(url: url, model: model, size: size, range: range, markers: markers) { _ in EmptyView() }
    }
}

// MARK: Trim

enum TrimOutput: Hashable { case video, gif }

struct TrimVideoEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var model: PlayerModel
    @State var info: VideoInfo?
    @State var range: ClosedRange<Double> = 0...1
    @State var output: TrimOutput = .video

    init(url: URL) {
        self.url = url
        _model = State(initialValue: PlayerModel(url: url))
    }

    private var duration: Double { info?.duration ?? 0 }
    private var changed: Bool { output == .gif || range.lowerBound > 0.01 || range.upperBound < duration - 0.01 }

    var body: some View {
        EditorScaffold(primaryTitle: output == .gif ? L("Export GIF", "GIF Aktar") : L("Trim", "Kes"), canApply: info != nil && changed, apply: apply) {
            VideoTimelineStage(url: url, model: model, size: info?.size ?? .zero, range: $range)
        } inspector: {
            InspectorSection(title: L("Selection", "Seçim"), symbol: "timeline.selection") {
                InfoRow(title: L("Start", "Başlangıç"), value: formatSeconds(range.lowerBound))
                InfoRow(title: L("End", "Bitiş"), value: formatSeconds(range.upperBound))
                InfoRow(title: L("Length", "Uzunluk"), value: formatSeconds(range.upperBound - range.lowerBound))
                HStack {
                    Button(L("Set In", "Giriş")) { range = min(model.time, range.upperBound - 0.1)...range.upperBound }
                        .keyboardShortcut("i", modifiers: [])
                    Button(L("Set Out", "Çıkış")) { range = range.lowerBound...max(model.time, range.lowerBound + 0.1) }
                        .keyboardShortcut("o", modifiers: [])
                }
                .buttonStyle(.glass).tint(nil)
                Button {
                    model.play(from: range.lowerBound, until: range.upperBound)
                } label: {
                    Label(L("Play Selected Range", "Seçili Aralığı Oynat"), systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).tint(nil)
            }
            InspectorSection(title: L("Output", "Çıktı"), symbol: "square.and.arrow.down") {
                ChoiceGrid(options: [(TrimOutput.video, L("Video", "Video")), (.gif, "GIF")], selection: $output, columns: 2)
                if output == .gif {
                    Text(L("GIFs are exported at 12 fps, 640 px wide, up to 30 seconds.", "GIF 12 fps, 640 px genişlik ve en fazla 30 saniye olarak aktarılır."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let info {
                InspectorSection(title: L("Source", "Kaynak"), symbol: "film") {
                    InfoRow(title: L("Resolution", "Çözünürlük"), value: "\(Int(info.size.width)) × \(Int(info.size.height))")
                    InfoRow(title: "FPS", value: String(format: "%.2f", info.fps))
                    InfoRow(title: L("Duration", "Süre"), value: formatSeconds(info.duration))
                }
            }
        } footer: {
            TransportBar(model: model, range: range)
        }
        .task {
            info = try? await VideoEditor.info(url)
            range = 0...max(duration, 0.1)
        }
        .onDisappear { model.stop() }
    }

    private func apply() {
        let url = url, range = range, output = output
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { progress in
            switch output {
            case .video: [try await VideoEditor.trim(url, range: range, progress: progress)]
            case .gif: [try await GIFMaker.make(from: url, range: range.lowerBound...min(range.upperBound, range.lowerBound + 30), progress: progress)]
            }
        }
        editor.close()
    }
}

// MARK: Crop

struct CropVideoEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var model: PlayerModel
    @State var info: VideoInfo?
    @State var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State var aspect: CropAspect = .free

    init(url: URL) {
        self.url = url
        _model = State(initialValue: PlayerModel(url: url))
    }

    private var size: CGSize { info?.size ?? .zero }

    var body: some View {
        EditorScaffold(primaryTitle: L("Crop", "Kırp"), canApply: rect != CGRect(x: 0, y: 0, width: 1, height: 1), apply: apply) {
            VideoTimelineStage(url: url, model: model, size: size) { fitted in
                CropSelector(rect: $rect, fitted: fitted, aspect: aspect.ratio(for: size))
            }
        } inspector: {
            InspectorSection(title: L("Aspect Ratio", "En Boy Oranı"), symbol: "aspectratio") {
                ChoiceGrid(options: CropAspect.allCases.map { ($0, $0.title) }, selection: $aspect)
            }
            InspectorSection(title: L("Output", "Çıktı"), symbol: "info.circle") {
                InfoRow(title: L("Size", "Boyut"), value: "\(Int(rect.width * size.width)) × \(Int(rect.height * size.height))")
                Button(L("Reset", "Sıfırla")) {
                    aspect = .free
                    rect = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
                .buttonStyle(.glass).tint(nil)
            }
        } footer: {
            TransportBar(model: model)
        }
        .onChange(of: aspect) { _, value in
            withAnimation(.snappy) { rect = CropSelector.centered(aspect: value.ratio(for: size), imageSize: size) }
        }
        .task { info = try? await VideoEditor.info(url) }
        .onDisappear { model.stop() }
    }

    private func apply() {
        let url = url, rect = rect
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { progress in
            [try await VideoEditor.crop(url, normalized: rect, progress: progress)]
        }
        editor.close()
    }
}

// MARK: Speed

struct SpeedEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var model: PlayerModel
    @State var info: VideoInfo?
    @State var speed = 2.0

    init(url: URL) {
        self.url = url
        _model = State(initialValue: PlayerModel(url: url))
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Change Speed", "Hızı Değiştir"), canApply: abs(speed - 1) > 0.01, apply: apply) {
            VideoTimelineStage(url: url, model: model, size: info?.size ?? .zero)
                .overlay(alignment: .topTrailing) {
                    StageMessage(text: String(format: "%.2g×", speed)).padding(14)
                }
        } inspector: {
            InspectorSection(title: L("Speed", "Hız"), symbol: "gauge.with.dots.needle.67percent") {
                ChoiceGrid(options: [(0.25, "0.25×"), (0.5, "0.5×"), (0.75, "0.75×"), (1.5, "1.5×"), (2.0, "2×"), (4.0, "4×")], selection: $speed)
                AdjustRow(title: L("Custom", "Özel"), value: $speed, range: 0.25...4, defaultValue: 1) { String(format: "%.2f×", $0) }
                Text(L("Pitch is preserved so voices sound natural.", "Perde korunur, sesler doğal kalır."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let info {
                InspectorSection(title: L("Duration", "Süre"), symbol: "clock") {
                    InfoRow(title: L("Original", "Orijinal"), value: formatSeconds(info.duration))
                    InfoRow(title: L("New", "Yeni"), value: formatSeconds(info.duration / speed))
                }
            }
        } footer: {
            TransportBar(model: model)
        }
        .onChange(of: speed) { _, value in
            model.rate = Float(value)
            if model.isPlaying { model.player.rate = Float(value) }
        }
        .task {
            info = try? await VideoEditor.info(url)
            model.rate = Float(speed)
        }
        .onDisappear { model.stop() }
    }

    private func apply() {
        let url = url, speed = speed
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { progress in
            [try await VideoEditor.changeSpeed(url, factor: speed, progress: progress)]
        }
        editor.close()
    }
}

// MARK: Frames

struct FramesEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var model: PlayerModel
    @State var info: VideoInfo?
    @State var times: [Double] = []
    @State var interval = 1.0
    @State var format: ConvertTarget = .png

    init(url: URL) {
        self.url = url
        _model = State(initialValue: PlayerModel(url: url))
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Export \(times.count) Frame(s)", "\(times.count) Kareyi Aktar"), canApply: !times.isEmpty, apply: apply) {
            VideoTimelineStage(url: url, model: model, size: info?.size ?? .zero, markers: times)
        } inspector: {
            InspectorSection(title: L("Pick Frames", "Kare Seç"), symbol: "photo.on.rectangle.angled") {
                Button {
                    add(model.time)
                } label: {
                    Label(L("Add Current Frame", "Bu Kareyi Ekle"), systemImage: "plus.viewfinder").frame(maxWidth: .infinity)
                }
                .keyboardShortcut("f", modifiers: [])
                AdjustRow(title: L("Every", "Her"), value: $interval, range: 0.5...30, defaultValue: 1) { String(format: L("%.1f s", "%.1f sn"), $0) }
                Button {
                    guard let duration = info?.duration, duration > 0 else { return }
                    times = Array(stride(from: 0, to: duration, by: max(interval, 0.1)).prefix(500))
                } label: {
                    Label(L("Fill at Interval", "Aralıkla Doldur"), systemImage: "square.grid.3x1.below.line.grid.1x2").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass).tint(nil)
            InspectorSection(title: L("Format", "Biçim"), symbol: "photo") {
                ChoiceGrid(options: ([.png, .jpeg, .heic, .tiff] as [ConvertTarget]).filter(ImageCapabilities.canWrite).map { ($0, $0.title) }, selection: $format, columns: 4)
            }
            InspectorSection(title: L("Frames", "Kareler"), symbol: "list.bullet") {
                if times.isEmpty {
                    Text(L("Press F or use the button to add frames.", "Kare eklemek için F’ye basın ya da düğmeyi kullanın."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(times.prefix(60), id: \.self) { time in
                    HStack {
                        Button(formatSeconds(time)) { model.seek(time) }
                            .buttonStyle(.plain)
                            .monospacedDigit()
                        Spacer()
                        Button { times.removeAll { $0 == time } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                    .font(.system(size: 12.5))
                }
                if times.count > 60 {
                    Text(L("+ \(times.count - 60) more", "+ \(times.count - 60) daha")).font(.caption).foregroundStyle(.secondary)
                }
                if !times.isEmpty {
                    Button(L("Clear", "Temizle")) { times.removeAll() }.buttonStyle(.glass).tint(nil)
                }
            }
        } footer: {
            TransportBar(model: model)
        }
        .task { info = try? await VideoEditor.info(url) }
        .onDisappear { model.stop() }
    }

    private func add(_ time: Double) {
        guard !times.contains(where: { abs($0 - time) < 0.02 }) else { return }
        times.append(time)
        times.sort()
    }

    private func apply() {
        let url = url, times = times, format = format
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { progress in
            try await VideoEditor.exportFrames(url, times: times, format: format, progress: progress)
        }
        editor.close()
    }
}

// MARK: Split

struct SplitVideoEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var model: PlayerModel
    @State var info: VideoInfo?
    @State var points: [Double] = []

    init(url: URL) {
        self.url = url
        _model = State(initialValue: PlayerModel(url: url))
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Split into \(points.count + 1) Parts", "\(points.count + 1) Parçaya Böl"), canApply: !points.isEmpty, apply: apply) {
            VideoTimelineStage(url: url, model: model, size: info?.size ?? .zero, markers: points)
        } inspector: {
            InspectorSection(title: L("Cuts", "Kesimler"), symbol: "scissors") {
                Button {
                    let time = model.time
                    guard time > 0.05, time < (info?.duration ?? 0) - 0.05, !points.contains(where: { abs($0 - time) < 0.05 }) else { return }
                    points.append(time)
                    points.sort()
                } label: {
                    Label(L("Cut at Playhead", "Oynatma Noktasında Kes"), systemImage: "scissors").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).tint(nil)
                .keyboardShortcut("s", modifiers: [])
                ForEach(points, id: \.self) { point in
                    HStack {
                        Button(formatSeconds(point)) { model.seek(point) }.buttonStyle(.plain).monospacedDigit()
                        Spacer()
                        Button { points.removeAll { $0 == point } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                    .font(.system(size: 12.5))
                }
                Text(L("Press S to cut at the playhead.", "Oynatma noktasında kesmek için S’ye basın."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            TransportBar(model: model)
        }
        .task { info = try? await VideoEditor.info(url) }
        .onDisappear { model.stop() }
    }

    private func apply() {
        let url = url, points = points
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { progress in
            try await VideoEditor.split(url, at: points, progress: progress)
        }
        editor.close()
    }
}

// MARK: Redact

struct RedactVideoEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var model: PlayerModel
    @State var info: VideoInfo?
    @State var regions: [CGRect] = []
    @State var style: RedactStyle = .blur

    init(url: URL) {
        self.url = url
        _model = State(initialValue: PlayerModel(url: url))
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Redact", "Gizle"), canApply: !regions.isEmpty, apply: apply) {
            VideoTimelineStage(url: url, model: model, size: info?.size ?? .zero) { fitted in
                RegionDrawer(regions: $regions, fitted: fitted)
            }
            .overlay(alignment: .top) {
                if regions.isEmpty {
                    StageMessage(text: L("Drag over areas to hide for the whole clip", "Klip boyunca gizlenecek alanların üzerinde sürükleyin")).padding(.top, 14)
                }
            }
        } inspector: {
            InspectorSection(title: L("Style", "Stil"), symbol: "eye.slash") {
                ChoiceGrid(options: [(RedactStyle.pixelate, L("Pixelate", "Pikselle")), (.blur, L("Blur", "Bulanık")), (.solid, L("Block", "Blok"))], selection: $style)
            }
            InspectorSection(title: L("Regions", "Bölgeler"), symbol: "square.dashed") {
                InfoRow(title: L("Regions", "Bölge"), value: "\(regions.count)")
                Button(L("Remove All", "Tümünü Kaldır")) { regions.removeAll() }
                    .buttonStyle(.glass).tint(nil)
                    .disabled(regions.isEmpty)
            }
        } footer: {
            TransportBar(model: model)
        }
        .task { info = try? await VideoEditor.info(url) }
        .onDisappear { model.stop() }
    }

    private func apply() {
        let url = url, regions = regions, style = style
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { progress in
            [try await VideoEditor.redact(url, regions: regions, style: style, progress: progress)]
        }
        editor.close()
    }
}

// MARK: Join

struct JoinVideosEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    @State var urls: [URL]
    @State var infos: [URL: VideoInfo] = [:]

    init(urls: [URL]) {
        _urls = State(initialValue: urls)
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Join", "Birleştir"), canApply: urls.count >= 2, apply: apply) {
            List {
                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(OrangeTheme.accent)
                            .frame(width: 22)
                        FileThumbnail(url: url, side: 64, radius: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            if let info = infos[url] {
                                Text("\(formatSeconds(info.duration)) · \(Int(info.size.width))×\(Int(info.size.height))")
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        Spacer()
                        Button { urls.removeAll { $0 == url } } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                }
                .onMove { source, destination in urls.move(fromOffsets: source, toOffset: destination) }
            }
            .scrollContentBackground(.hidden)
            .environment(\.colorScheme, .dark)
            .padding(10)
        } inspector: {
            InspectorSection(title: L("Sequence", "Sıra"), symbol: "rectangle.stack") {
                InfoRow(title: L("Clips", "Klip"), value: "\(urls.count)")
                InfoRow(title: L("Total", "Toplam"), value: formatSeconds(urls.reduce(0) { $0 + (infos[$1]?.duration ?? 0) }))
                if let first = urls.first.flatMap({ infos[$0] }) {
                    InfoRow(title: L("Frame size", "Kare boyutu"), value: "\(Int(first.size.width))×\(Int(first.size.height))")
                }
                Text(L("Clips are fitted to the first clip’s frame. Drag to reorder.", "Klipler ilk klibin karesine sığdırılır. Sıralamak için sürükleyin."))
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { urls += await runtime.chooseFiles(kinds: [.video]) }
                } label: {
                    Label(L("Add Clips…", "Klip Ekle…"), systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).tint(nil)
            }
        }
        .task(id: urls) {
            for url in urls where infos[url] == nil {
                infos[url] = try? await VideoEditor.info(url)
            }
        }
    }

    private func apply() {
        let urls = urls
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: L("\(urls.count) clips", "\(urls.count) klip")) { progress in
            [try await VideoEditor.join(urls, progress: progress)]
        }
        editor.close()
    }
}

// MARK: Compress

struct CompressVideoEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var urls: [URL]
    @State var model: PlayerModel
    @State var info: VideoInfo?
    @State var quality: VideoQuality = .balanced

    init(urls: [URL]) {
        self.urls = urls
        _model = State(initialValue: PlayerModel(url: urls[0]))
    }

    var body: some View {
        EditorScaffold(primaryTitle: urls.count > 1 ? L("Compress \(urls.count) Videos", "\(urls.count) Videoyu Sıkıştır") : L("Compress", "Sıkıştır"), apply: apply) {
            VideoTimelineStage(url: urls[0], model: model, size: info?.size ?? .zero)
        } inspector: {
            InspectorSection(title: L("Quality", "Kalite"), symbol: "dial.medium") {
                ForEach(VideoQuality.allCases, id: \.self) { option in
                    let selected = option == quality
                    Button {
                        withAnimation(.snappy) { quality = option }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(option)).font(.system(size: 18)).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(option)).font(.system(size: 13, weight: .semibold))
                                Text(detail(option)).font(.caption).opacity(0.75)
                            }
                            Spacer()
                        }
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(selected ? .regular.tint(OrangeTheme.accent).interactive() : .regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            if let info {
                InspectorSection(title: L("Source", "Kaynak"), symbol: "film") {
                    InfoRow(title: L("Resolution", "Çözünürlük"), value: "\(Int(info.size.width)) × \(Int(info.size.height))")
                    InfoRow(title: L("Duration", "Süre"), value: formatSeconds(info.duration))
                    InfoRow(title: L("Size", "Boyut"), value: ByteCountFormatter.string(fromByteCount: fileSize(urls[0]), countStyle: .file))
                }
            }
        } footer: {
            TransportBar(model: model)
        }
        .task { info = try? await VideoEditor.info(urls[0]) }
        .onDisappear { model.stop() }
    }

    private func title(_ option: VideoQuality) -> String {
        switch option {
        case .small: L("Smallest", "En Küçük")
        case .balanced: L("Balanced", "Dengeli")
        case .high: L("High Quality", "Yüksek Kalite")
        }
    }

    private func detail(_ option: VideoQuality) -> String {
        switch option {
        case .small: L("540p H.264 · great for messages", "540p H.264 · mesajlar için ideal")
        case .balanced: L("1080p HEVC · sharp and compact", "1080p HEVC · net ve kompakt")
        case .high: L("Original size HEVC · near lossless", "Orijinal boyut HEVC · kayıpsıza yakın")
        }
    }

    private func symbol(_ option: VideoQuality) -> String {
        switch option {
        case .small: "paperplane"
        case .balanced: "scalemass"
        case .high: "sparkles"
        }
    }

    private func apply() {
        let quality = quality
        runtime.runEach(urls, title: editor.tool.windowTitle, symbol: editor.tool.symbol) { url, progress in
            [try await VideoEditor.compress(url, quality: quality, progress: progress)]
        }
        editor.close()
    }
}
