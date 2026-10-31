import AppKit
import OrangeKit
import SwiftUI

struct WaveLaneLabel: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AudioLoadingView: View {
    var audio: AudioModel

    var body: some View {
        if let failed = audio.failed {
            EmptyHint(symbol: "exclamationmark.triangle", title: L("Couldn’t open audio", "Ses açılamadı"), message: failed)
                .environment(\.colorScheme, .dark)
        } else {
            VStack(spacing: 10) {
                ProgressView().controlSize(.large)
                Text(L("Reading waveform…", "Dalga formu okunuyor…")).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: Trim

struct TrimAudioEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var audio = AudioModel()
    @State var model: PlayerModel
    @State var range: ClosedRange<Double> = 0...1
    @State var trimSilence = false

    init(url: URL) {
        self.url = url
        _model = State(initialValue: PlayerModel(url: url))
    }

    private var duration: Double { audio.clip?.duration ?? 0 }

    var body: some View {
        EditorScaffold(primaryTitle: L("Apply", "Uygula"), canApply: audio.clip != nil && (range.lowerBound > 0.005 || range.upperBound < duration - 0.005), apply: apply) {
            if audio.clip == nil {
                AudioLoadingView(audio: audio)
            } else {
                VStack(spacing: 22) {
                    Spacer()
                    Text(L("\(formatSeconds(range.upperBound - range.lowerBound)) selected", "\(formatSeconds(range.upperBound - range.lowerBound)) seçili"))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    RangeTimeline(duration: max(duration, 0.01), range: $range, playhead: model.time, height: 150, onSeek: { model.seek($0) }) {
                        WaveformView(peaks: audio.peaks)
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text(L("Start", "Başlangıç")).font(.caption).foregroundStyle(.white.opacity(0.5))
                            Text(formatSeconds(range.lowerBound)).monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(L("End", "Bitiş")).font(.caption).foregroundStyle(.white.opacity(0.5))
                            Text(formatSeconds(range.upperBound)).monospacedDigit()
                        }
                    }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    Spacer()
                }
                .padding(28)
            }
        } inspector: {
            InspectorSection(title: L("Selection", "Seçim"), symbol: "timeline.selection") {
                Toggle(L("Trim silent ends automatically", "Sessiz uçları otomatik kırp"), isOn: $trimSilence)
                    .toggleStyle(.checkbox)
                HStack {
                    Button(L("Set In", "Giriş")) { range = min(model.time, range.upperBound - 0.05)...range.upperBound }
                        .keyboardShortcut("i", modifiers: [])
                    Button(L("Set Out", "Çıkış")) { range = range.lowerBound...max(model.time, range.lowerBound + 0.05) }
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
            InspectorSection(title: L("Source", "Kaynak"), symbol: "waveform") {
                InfoRow(title: L("Duration", "Süre"), value: formatSeconds(duration))
                if let clip = audio.clip {
                    InfoRow(title: L("Channels", "Kanal"), value: clip.channelCount == 1 ? "Mono" : "Stereo")
                    InfoRow(title: L("Sample rate", "Örnekleme"), value: "\(Int(clip.sampleRate)) Hz")
                }
            }
        } footer: {
            TransportBar(model: model, range: range)
        }
        .task {
            await audio.load(url)
            range = 0...max(duration, 0.01)
        }
        .onChange(of: trimSilence) { _, on in
            guard let clip = audio.clip else { return }
            withAnimation(.snappy) { range = on ? clip.silenceBounds() : 0...clip.duration }
        }
        .onDisappear { model.stop() }
    }

    private func apply() {
        guard let clip = audio.clip else { return }
        let url = url, range = range
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            [try AudioEngine.save(clip.trimmed(range.lowerBound, range.upperBound), from: url, suffix: L("Trimmed", "Kesilmiş"))]
        }
        editor.close()
    }
}

// MARK: Channels

struct ChannelsEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var audio = AudioModel()
    @State var model: PlayerModel
    @State var toMono = true
    @State var left = 1.0
    @State var right = 1.0
    @State var previewing = false

    init(url: URL) {
        self.url = url
        _model = State(initialValue: PlayerModel(url: url))
    }

    private var output: AudioClip? {
        audio.clip?.remixed(toMono: toMono, gains: [left, right])
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Apply", "Uygula"), canApply: audio.clip != nil, busy: previewing, apply: apply) {
            if audio.clip == nil {
                AudioLoadingView(audio: audio)
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    ForEach(Array(audio.channelPeaks.enumerated()), id: \.offset) { index, peaks in
                        VStack(spacing: 6) {
                            WaveLaneLabel(title: audio.channelPeaks.count == 1 ? "MONO" : (index == 0 ? L("LEFT", "SOL") : L("RIGHT", "SAĞ")))
                            WaveformView(peaks: peaks.map { $0 * Float(index == 0 ? left : right) }, color: index == 0 ? OrangeTheme.accent.opacity(0.9) : Color.pink.opacity(0.85))
                                .frame(height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    WaveLaneLabel(title: L("OUTPUT · \(toMono ? "MONO" : "STEREO")", "ÇIKTI · \(toMono ? "MONO" : "STEREO")"))
                    WaveformView(peaks: output?.peaks(buckets: 500) ?? [], color: .white.opacity(0.85))
                        .frame(height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                }
                .padding(28)
            }
        } inspector: {
            InspectorSection(title: L("Channels", "Kanallar"), symbol: "hifispeaker.2") {
                Picker("", selection: $toMono) {
                    Text("Mono").tag(true)
                    Text("Stereo").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                AdjustRow(title: toMono ? L("Level", "Seviye") : L("Left", "Sol"), value: $left, range: 0...2, defaultValue: 1) { "\(Int(($0 * 100).rounded()))%" }
                if !toMono {
                    AdjustRow(title: L("Right", "Sağ"), value: $right, range: 0...2, defaultValue: 1) { "\(Int(($0 * 100).rounded()))%" }
                }
            }
            InspectorSection(title: L("Listen", "Dinle"), symbol: "headphones") {
                Button { playOutput() } label: {
                    Label(L("Play Output", "Çıktıyı Oynat"), systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                Button {
                    model.replace(with: url)
                    model.play()
                } label: {
                    Label(L("Play Original", "Orijinali Oynat"), systemImage: "play").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass).tint(nil)
        } footer: {
            TransportBar(model: model)
        }
        .task { await audio.load(url) }
        .onDisappear { model.stop() }
    }

    private func playOutput() {
        guard let output else { return }
        previewing = true
        Task {
            let file = PreviewFiles.url("caf")
            let ok = await Task.detached { (try? output.write(to: file)) != nil }.value
            previewing = false
            if ok {
                model.replace(with: file)
                try? await Task.sleep(for: .milliseconds(150))
                model.play()
            }
        }
    }

    private func apply() {
        guard let output else { return }
        let url = url, toMono = toMono
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            [try AudioEngine.save(output, from: url, suffix: toMono ? "Mono" : "Stereo")]
        }
        editor.close()
    }
}

// MARK: Bleep

struct BleepEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var audio = AudioModel()
    @State var model: PlayerModel
    @State var bleeps: [ClosedRange<Double>] = []
    @State var draft: ClosedRange<Double>?
    @State var tone = true
    @State var frequency = 1000.0
    @State var previewing = false

    init(url: URL) {
        self.url = url
        _model = State(initialValue: PlayerModel(url: url))
    }

    private var duration: Double { audio.clip?.duration ?? 0 }

    var body: some View {
        EditorScaffold(primaryTitle: L("Apply", "Uygula"), canApply: !bleeps.isEmpty, busy: previewing, apply: apply) {
            if audio.clip == nil {
                AudioLoadingView(audio: audio)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    WaveLaneLabel(title: L("BLEEP", "BİP"))
                    bleepLane.frame(height: 48)
                    WaveLaneLabel(title: L("AUDIO", "SES"))
                    RangeTimeline(duration: max(duration, 0.01), range: .constant(0...max(duration, 0.01)), playhead: model.time, markers: [], editable: false, height: 150, onSeek: { model.seek($0) }) {
                        WaveformView(peaks: audio.peaks)
                    }
                    Text(L("Drag on the Bleep lane over a word to censor it. Press B to bleep half a second at the playhead.", "Sansürlemek için kelimenin üstünde Bip şeridinde sürükleyin. Oynatma noktasına yarım saniyelik bip için B’ye basın."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(28)
            }
        } inspector: {
            InspectorSection(title: L("Sound", "Ses"), symbol: "speaker.wave.2") {
                ChoiceGrid(options: [(true, L("Tone", "Ton")), (false, L("Silence", "Sessizlik"))], selection: $tone, columns: 2)
                if tone {
                    AdjustRow(title: L("Pitch", "Perde"), value: $frequency, range: 300...2500, defaultValue: 1000) { "\(Int($0)) Hz" }
                }
            }
            InspectorSection(title: L("Bleeps", "Bipler"), symbol: "list.bullet") {
                Button {
                    let start = model.time
                    add(start...min(start + 0.5, duration))
                } label: {
                    Label(L("Bleep at Playhead", "Oynatma Noktasına Bip"), systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).tint(nil)
                .keyboardShortcut("b", modifiers: [])
                ForEach(Array(bleeps.enumerated()), id: \.offset) { index, bleep in
                    HStack {
                        Button("\(formatSeconds(bleep.lowerBound)) – \(formatSeconds(bleep.upperBound))") { model.seek(bleep.lowerBound) }
                            .buttonStyle(.plain)
                            .monospacedDigit()
                        Spacer()
                        Button { bleeps.remove(at: index) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                    .font(.system(size: 12.5))
                }
            }
        } footer: {
            Button(L("Preview Original", "Orijinali Dinle")) {
                model.replace(with: url)
                model.play()
            }
            .buttonStyle(.glass).tint(nil)
            Button(L("With Bleeps", "Bipli Dinle")) { preview() }
                .buttonStyle(.glass).tint(nil)
                .disabled(bleeps.isEmpty)
            TransportBar(model: model)
        }
        .task { await audio.load(url) }
        .onDisappear { model.stop() }
    }

    private var bleepLane: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let scale = duration > 0 ? width / duration : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                ForEach(Array((bleeps + (draft.map { [$0] } ?? [])).enumerated()), id: \.offset) { _, bleep in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(OrangeTheme.accentGradient)
                        .overlay(Image(systemName: "waveform.badge.exclamationmark").font(.system(size: 11)).foregroundStyle(.white))
                        .frame(width: max(4, (bleep.upperBound - bleep.lowerBound) * scale), height: 36)
                        .offset(x: bleep.lowerBound * scale)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let a = min(max(value.startLocation.x / max(scale, 0.0001), 0), duration)
                        let b = min(max(value.location.x / max(scale, 0.0001), 0), duration)
                        draft = min(a, b)...max(a, b)
                    }
                    .onEnded { _ in
                        if let draft, draft.upperBound - draft.lowerBound > 0.05 { add(draft) }
                        draft = nil
                    }
            )
        }
    }

    private func add(_ range: ClosedRange<Double>) {
        bleeps.append(range)
        bleeps.sort { $0.lowerBound < $1.lowerBound }
    }

    private func preview() {
        guard let clip = audio.clip else { return }
        previewing = true
        let bleeps = bleeps, tone = tone, frequency = frequency
        Task {
            let file = PreviewFiles.url("caf")
            let ok = await Task.detached { (try? clip.bleeped(bleeps, tone: tone, frequency: frequency).write(to: file)) != nil }.value
            previewing = false
            if ok {
                model.replace(with: file)
                try? await Task.sleep(for: .milliseconds(150))
                model.play(from: max(0, (bleeps.first?.lowerBound ?? 0) - 1.5))
            }
        }
    }

    private func apply() {
        guard let clip = audio.clip else { return }
        let url = url, bleeps = bleeps, tone = tone, frequency = frequency
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { _ in
            [try AudioEngine.save(clip.bleeped(bleeps, tone: tone, frequency: frequency), from: url, suffix: L("Bleeped", "Bipli"))]
        }
        editor.close()
    }
}

// MARK: Level

struct LevelEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var urls: [URL]
    @State var audio = AudioModel()
    @State var mode: AudioClip.Normalization = .loudness
    @State var target = -16.0

    init(urls: [URL]) {
        self.urls = urls
    }

    private var gain: Double {
        guard let clip = audio.clip else { return 0 }
        switch mode {
        case .peak: return target - AudioClip.decibels(clip.peak)
        case .loudness: return min(target - AudioClip.decibels(clip.rms), -1 - AudioClip.decibels(clip.peak))
        }
    }

    var body: some View {
        EditorScaffold(primaryTitle: urls.count > 1 ? L("Normalize \(urls.count) Files", "\(urls.count) Dosyayı Dengele") : L("Normalize", "Dengele"), canApply: audio.clip != nil, apply: apply) {
            if audio.clip == nil {
                AudioLoadingView(audio: audio)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    WaveLaneLabel(title: L("BEFORE", "ÖNCE"))
                    WaveformView(peaks: audio.peaks, color: .white.opacity(0.5))
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    WaveLaneLabel(title: L("AFTER", "SONRA"))
                    WaveformView(peaks: audio.peaks.map { min(1, $0 * Float(pow(10, gain / 20))) }, color: OrangeTheme.accent)
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(String(format: "%+.1f dB", gain))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    Spacer()
                }
                .padding(28)
            }
        } inspector: {
            InspectorSection(title: L("Method", "Yöntem"), symbol: "dial.medium") {
                ChoiceGrid(options: [(AudioClip.Normalization.loudness, L("Loudness", "Yükseklik")), (.peak, L("Peak", "Tepe"))], selection: $mode, columns: 2)
                AdjustRow(title: L("Target", "Hedef"), value: $target, range: mode == .peak ? -12...0 : -30...(-8), defaultValue: mode == .peak ? -1 : -16) { String(format: "%.1f dB", $0) }
                Text(mode == .peak
                     ? L("Raises the loudest moment to the target.", "En yüksek anı hedefe taşır.")
                     : L("Matches average loudness, with a −1 dB safety limit.", "Ortalama yüksekliği eşitler, −1 dB güvenlik sınırıyla."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let clip = audio.clip {
                InspectorSection(title: L("Analysis", "Analiz"), symbol: "chart.bar") {
                    InfoRow(title: L("Peak", "Tepe"), value: String(format: "%.1f dBFS", AudioClip.decibels(clip.peak)))
                    InfoRow(title: "RMS", value: String(format: "%.1f dBFS", AudioClip.decibels(clip.rms)))
                    if urls.count > 1 {
                        Text(L("Each file is analyzed separately.", "Her dosya ayrı analiz edilir.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: mode) { _, value in target = value == .peak ? -1 : -16 }
        .task { await audio.load(urls[0]) }
    }

    private func apply() {
        let mode = mode, target = target
        runtime.runEach(urls, title: editor.tool.windowTitle, symbol: editor.tool.symbol) { url, _ in
            let clip = try await AudioClip.load(url)
            return [try AudioEngine.save(clip.normalized(mode, target: target), from: url, suffix: L("Normalized", "Dengelenmiş"))]
        }
        editor.close()
    }
}

// MARK: Audio to video

enum VisualizerFrame: String, Hashable {
    case square, portrait, landscape

    var size: CGSize {
        switch self {
        case .square: CGSize(width: 1080, height: 1080)
        case .portrait: CGSize(width: 1080, height: 1920)
        case .landscape: CGSize(width: 1920, height: 1080)
        }
    }
}

struct AudioToVideoEditor: View {
    @Environment(\.editor) private var editor
    @Environment(AppRuntime.self) private var runtime
    var url: URL
    @State var shape: VisualizerStyle.Shape = .bars
    @State var frame: VisualizerFrame = .square
    @State var palette = 0
    @State var artwork: URL?
    @State var preview: CGImage?

    static let palettes: [([RGBA], RGBA)] = [
        ([RGBA(hex: 0x2A0E3A), RGBA(hex: 0xF0522B)], RGBA(hex: 0xFFD08A)),
        ([RGBA(hex: 0x0F2027), RGBA(hex: 0x2C5364)], RGBA(hex: 0x7CF5FF)),
        ([RGBA(hex: 0x1D0B3A), RGBA(hex: 0x8E2DE2)], RGBA(hex: 0xFF9DE6)),
        ([RGBA(hex: 0xFFE7B3), RGBA(hex: 0xFF8A3D)], RGBA(hex: 0x3A1404)),
        ([RGBA(hex: 0x000000), RGBA(hex: 0x1C1C1E)], RGBA(1, 1, 1)),
        ([RGBA(hex: 0x134E5E), RGBA(hex: 0x71B280)], RGBA(hex: 0xF9F871))
    ]

    private var style: VisualizerStyle {
        var style = VisualizerStyle()
        style.shape = shape
        style.size = frame.size
        style.colors = Self.palettes[palette].0
        style.accent = Self.palettes[palette].1
        style.artwork = artwork
        return style
    }

    var body: some View {
        EditorScaffold(primaryTitle: L("Create Video", "Video Oluştur"), apply: apply) {
            ImageStage(image: preview)
        } inspector: {
            InspectorSection(title: L("Visual", "Görsel"), symbol: "waveform") {
                ChoiceGrid(options: [(VisualizerStyle.Shape.bars, L("Bars", "Çubuk")), (.wave, L("Wave", "Dalga")), (.pulse, L("Pulse", "Nabız"))], selection: $shape)
            }
            InspectorSection(title: L("Colors", "Renkler"), symbol: "paintpalette") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Array(Self.palettes.enumerated()), id: \.offset) { index, entry in
                        Button { palette = index } label: {
                            LinearGradient(colors: entry.0.map { Color($0) }, startPoint: .bottomLeading, endPoint: .topTrailing)
                                .overlay(Circle().fill(Color(entry.1)).frame(width: 10, height: 10))
                                .frame(height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette == index ? OrangeTheme.accent : .clear, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            InspectorSection(title: L("Frame", "Kare"), symbol: "aspectratio") {
                ChoiceGrid(options: [(VisualizerFrame.square, "1:1"), (.portrait, "9:16"), (.landscape, "16:9")], selection: $frame)
            }
            InspectorSection(title: L("Artwork", "Kapak"), symbol: "photo") {
                HStack {
                    Button(artwork == nil ? L("Choose Image…", "Görsel Seç…") : L("Change…", "Değiştir…")) {
                        Task { artwork = await runtime.chooseFiles(kinds: [.image], multiple: false).first }
                    }
                    if artwork != nil {
                        Button(L("Remove", "Kaldır")) { artwork = nil }
                    }
                }
                .buttonStyle(.glass).tint(nil)
            }
        }
        .task(id: [AnyHashable(shape), AnyHashable(frame), AnyHashable(palette), AnyHashable(artwork)]) {
            let style = style
            preview = await Task.detached { try? Visualizer.previewFrame(style: style) }.value
        }
    }

    private func apply() {
        let url = url, style = style
        runtime.run(editor.tool.windowTitle, symbol: editor.tool.symbol, detail: url.lastPathComponent) { progress in
            [try await Visualizer.render(audio: url, style: style, progress: progress)]
        }
        editor.close()
    }
}
