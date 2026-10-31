@preconcurrency import AVFoundation
import AVKit
import OrangeKit
import SwiftUI

@MainActor
@Observable
final class PlayerModel {
    private(set) var player: AVPlayer
    var time: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var rate: Float = 1
    private var stopAt: Double?
    private var observer: Any?

    init(url: URL) {
        player = AVPlayer(url: url)
        attach()
        load(url)
    }

    private func attach() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    private func load(_ url: URL) {
        Task {
            let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            duration = seconds.isFinite ? seconds : 0
        }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        time = seconds
        isPlaying = player.rate != 0
        if let stopAt, seconds >= stopAt {
            player.pause()
            self.stopAt = nil
            isPlaying = false
        }
    }

    func play(from start: Double? = nil, until end: Double? = nil) {
        if let start { seek(start) }
        if time >= duration - 0.05, start == nil { seek(0) }
        stopAt = end
        player.rate = rate
        isPlaying = true
    }

    func pause() {
        player.pause()
        stopAt = nil
        isPlaying = false
    }

    func toggle(range: ClosedRange<Double>? = nil) {
        if isPlaying {
            pause()
        } else if let range {
            play(from: time >= range.lowerBound && time < range.upperBound - 0.05 ? nil : range.lowerBound, until: range.upperBound)
        } else {
            play()
        }
    }

    func seek(_ seconds: Double) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        time = clamped
    }

    func replace(with url: URL) {
        pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        load(url)
    }

    func stop() {
        pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
    }
}

struct VideoSurface: NSViewRepresentable {
    var player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

struct VideoStage<Overlay: View>: View {
    var model: PlayerModel
    var size: CGSize
    var overlay: (CGRect) -> Overlay

    init(model: PlayerModel, size: CGSize, @ViewBuilder overlay: @escaping (CGRect) -> Overlay) {
        self.model = model
        self.size = size
        self.overlay = overlay
    }

    var body: some View {
        if size.width > 0 {
            FittedStage(contentSize: size) {
                VideoSurface(player: model.player)
            } overlay: { fitted in
                overlay(fitted)
            }
        } else {
            ProgressView().controlSize(.large)
        }
    }
}

extension VideoStage where Overlay == EmptyView {
    init(model: PlayerModel, size: CGSize) {
        self.init(model: model, size: size) { _ in EmptyView() }
    }
}

struct TransportBar: View {
    var model: PlayerModel
    var range: ClosedRange<Double>?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.toggle(range: range)
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.glass).tint(nil)
            .buttonBorderShape(.circle)
            .keyboardShortcut(.space, modifiers: [])
            Text("\(formatSeconds(model.time)) / \(formatSeconds(model.duration))")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: Timeline

struct RangeTimeline<Background: View>: View {
    var duration: Double
    @Binding var range: ClosedRange<Double>
    var playhead: Double
    var markers: [Double] = []
    var handleColor: Color = OrangeTheme.ember
    var editable = true
    var height: CGFloat = 64
    var onSeek: (Double) -> Void
    @ViewBuilder var background: Background

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let scale = duration > 0 ? width / duration : 0
            let lower = range.lowerBound * scale
            let upper = range.upperBound * scale
            ZStack(alignment: .topLeading) {
                background
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in onSeek(clamp(value.location.x / max(scale, 0.0001))) }
                    )
                if editable {
                Rectangle().fill(.black.opacity(0.55))
                    .frame(width: max(0, lower), height: height)
                    .allowsHitTesting(false)
                Rectangle().fill(.black.opacity(0.55))
                    .frame(width: max(0, width - upper), height: height)
                    .offset(x: upper)
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(handleColor, lineWidth: 3)
                    .frame(width: max(6, upper - lower), height: height)
                    .offset(x: lower)
                    .allowsHitTesting(false)
                }
                ForEach(markers, id: \.self) { marker in
                    Rectangle().fill(Color.yellow)
                        .frame(width: 2, height: height + 8)
                        .offset(x: marker * scale - 1, y: -4)
                        .allowsHitTesting(false)
                }
                Capsule().fill(.white)
                    .frame(width: 2.5, height: height + 12)
                    .shadow(radius: 2)
                    .offset(x: playhead * scale - 1.25, y: -6)
                    .allowsHitTesting(false)
                if editable {
                handle(at: lower, height: height) { x in
                    let value = clamp(x / max(scale, 0.0001))
                    range = min(value, range.upperBound - minimumSpan)...range.upperBound
                    onSeek(range.lowerBound)
                }
                handle(at: upper, height: height) { x in
                    let value = clamp(x / max(scale, 0.0001))
                    range = range.lowerBound...max(value, range.lowerBound + minimumSpan)
                    onSeek(range.upperBound)
                }
                }
            }
            .coordinateSpace(.named("timeline"))
        }
        .frame(height: height)
    }

    private var minimumSpan: Double { min(0.1, duration / 2) }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), duration)
    }

    private func handle(at x: CGFloat, height: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(handleColor)
            .frame(width: 12, height: height + 6)
            .overlay(Capsule().fill(.white.opacity(0.85)).frame(width: 2, height: 18))
            .shadow(color: .black.opacity(0.3), radius: 3)
            .frame(width: 26, height: height + 6)
            .contentShape(Rectangle())
            .offset(x: x - 13, y: -3)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                    .onChanged { value in onDrag(value.location.x) }
            )
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}

struct WaveformView: View {
    var peaks: [Float]
    var color: Color = .white.opacity(0.85)

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let bar = size.width / CGFloat(peaks.count)
            var path = Path()
            for (index, peak) in peaks.enumerated() {
                let height = max(1, CGFloat(peak) * size.height * 0.92)
                path.addRoundedRect(
                    in: CGRect(x: CGFloat(index) * bar, y: (size.height - height) / 2, width: max(1, bar * 0.7), height: height),
                    cornerSize: CGSize(width: 0.5, height: 0.5)
                )
            }
            context.fill(path, with: .color(color))
        }
        .background(Color.white.opacity(0.05))
    }
}

struct ThumbnailStrip: View {
    var url: URL
    @State var frames: [CGImage] = []

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .background(Color.white.opacity(0.06))
        .task(id: url) {
            frames = await VideoEditor.thumbnails(url, count: 12, maxSide: 180)
        }
    }
}

/// Decodes audio once for waveform display.
@MainActor
@Observable
final class AudioModel {
    var clip: AudioClip?
    var peaks: [Float] = []
    var channelPeaks: [[Float]] = []
    var failed: String?

    func load(_ url: URL) async {
        do {
            let clip = try await Task.detached { try await AudioClip.load(url) }.value
            let peaks = await Task.detached { clip.peaks(buckets: 700) }.value
            let channels = await Task.detached { clip.channelPeaks(buckets: 500) }.value
            self.clip = clip
            self.peaks = peaks
            self.channelPeaks = channels
        } catch {
            failed = error.orangeMessage
        }
    }
}

/// Writes a temporary file for previews and plays it.
enum PreviewFiles {
    static func url(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("orange-preview-\(UUID().uuidString)").appendingPathExtension(ext)
    }
}
