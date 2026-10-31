@preconcurrency import AVFoundation
import Accelerate
import CoreGraphics
import CoreVideo
import Foundation

public struct VisualizerStyle: Hashable, Sendable {
    public enum Shape: String, CaseIterable, Sendable {
        case bars, wave, pulse
    }

    public var shape: Shape = .bars
    public var size = CGSize(width: 1080, height: 1080)
    public var fps = 30
    public var colors: [RGBA] = [RGBA(hex: 0x2A0E3A), RGBA(hex: 0xF0522B)]
    public var accent = RGBA(hex: 0xFFD08A)
    public var artwork: URL?

    public init() {}
}

public enum Visualizer {
    public static func render(audio url: URL, style: VisualizerStyle, progress: ProgressHandler?) async throws -> URL {
        let clip = try await AudioClip.load(url)
        guard clip.frameCount > 0 else { throw OrangeError.empty }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("orange-visualizer-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: temp) }
        try await writeFrames(clip: clip, style: style, to: temp) { progress?($0 * 0.8) }

        let composition = AVMutableComposition()
        let video = AVURLAsset(url: temp)
        let audio = AVURLAsset(url: url)
        guard let videoSource = try await video.loadTracks(withMediaType: .video).first,
              let audioSource = try await audio.loadTracks(withMediaType: .audio).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw OrangeError.writeFailed("visualizer")
        }
        let duration = try await audio.load(.duration)
        let span = CMTimeRange(start: .zero, duration: duration)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: try await video.load(.duration)), of: videoSource, at: .zero)
        try audioTrack.insertTimeRange(span, of: audioSource, at: .zero)
        let output = VideoEditor.destination(for: url, suffix: nil, ext: "mp4")
        try await VideoEditor.export(composition, preset: AVAssetExportPresetPassthrough, to: output) { progress?(0.8 + $0 * 0.2) }
        return output
    }

    static func writeFrames(clip: AudioClip, style: VisualizerStyle, to url: URL, progress: ProgressHandler) async throws {
        let width = Int(style.size.width)
        let height = Int(style.size.height)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw OrangeError.writeFailed("visualizer") }
        writer.startSession(atSourceTime: .zero)

        let artwork = style.artwork.flatMap { try? ImageEngine.load($0, maxPixel: 1200) }
        let mixed = clip.mono()
        let totalFrames = max(1, Int(clip.duration * Double(style.fps)))
        let samplesPerFrame = max(1, Int(clip.sampleRate) / style.fps)
        let bandCount = 48
        var smoothed = [Float](repeating: 0, count: bandCount)

        for index in 0..<totalFrames {
            if Task.isCancelled {
                writer.cancelWriting()
                throw OrangeError.cancelled
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let start = min(index * samplesPerFrame, mixed.count)
            let window = Array(mixed[start..<min(start + samplesPerFrame * 2, mixed.count)])
            let bands = levels(window, count: bandCount)
            for band in 0..<bandCount {
                smoothed[band] = max(bands[band], smoothed[band] * 0.82)
            }
            guard let pool = adaptor.pixelBufferPool else { throw OrangeError.writeFailed("visualizer") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw OrangeError.writeFailed("visualizer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: ImageEngine.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                draw(context: context, size: CGSize(width: width, height: height), levels: smoothed, wave: window, style: style, artwork: artwork)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(style.fps)))
            if index % 15 == 0 { progress(Double(index) / Double(totalFrames)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw OrangeError.writeFailed("visualizer") }
    }

    /// A representative still for previews.
    public static func previewFrame(style: VisualizerStyle, maxSide: CGFloat = 540) throws -> CGImage {
        let scale = maxSide / max(style.size.width, style.size.height)
        let size = CGSize(width: (style.size.width * scale).rounded(), height: (style.size.height * scale).rounded())
        var scaled = style
        scaled.size = size
        let levels = (0..<48).map { index -> Float in
            let x = Float(index) / 47
            return 0.25 + 0.6 * abs(sin(x * 7.3) * cos(x * 2.1))
        }
        let wave = (0..<1470).map { index in 0.5 * Float(sin(Double(index) / 18) * sin(Double(index) / 210)) }
        let artwork = style.artwork.flatMap { try? ImageEngine.load($0, maxPixel: 800) }
        return try ImageEngine.render(width: Int(size.width), height: Int(size.height)) { context in
            draw(context: context, size: size, levels: levels, wave: wave, style: scaled, artwork: artwork)
        }
    }

    static func levels(_ samples: [Float], count: Int) -> [Float] {
        guard !samples.isEmpty else { return [Float](repeating: 0, count: count) }
        let size = max(1, samples.count / count)
        return (0..<count).map { band in
            let start = min(band * size, samples.count - 1)
            let end = min(start + size, samples.count)
            let slice = Array(samples[start..<end])
            let rms = slice.isEmpty ? 0 : vDSP.rootMeanSquare(slice)
            return min(1, sqrt(rms) * 1.6)
        }
    }

    static func draw(context: CGContext, size: CGSize, levels: [Float], wave: [Float], style: VisualizerStyle, artwork: CGImage?) {
        let rect = CGRect(origin: .zero, size: size)
        Backdrop.paint(.gradient(style.colors), in: rect, context: context)
        let energy = CGFloat(levels.reduce(0, +) / Float(max(levels.count, 1)))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let accent = style.accent.cgColor

        if let artwork {
            let side = min(size.width, size.height) * (0.42 + energy * 0.04)
            let box = CGRect(x: center.x - side / 2, y: center.y - side / 2 + size.height * 0.08, width: side, height: side)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: CGColor(gray: 0, alpha: 0.45))
            context.addPath(CGPath(roundedRect: box, cornerWidth: side * 0.08, cornerHeight: side * 0.08, transform: nil))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillPath()
            context.restoreGState()
            context.saveGState()
            context.addPath(CGPath(roundedRect: box, cornerWidth: side * 0.08, cornerHeight: side * 0.08, transform: nil))
            context.clip()
            context.draw(artwork, in: Collage.aspectFill(CGSize(width: artwork.width, height: artwork.height), in: box))
            context.restoreGState()
        }

        switch style.shape {
        case .bars:
            let baseline = artwork == nil ? size.height * 0.5 : size.height * 0.18
            let span = size.width * 0.8
            let gap: CGFloat = span / CGFloat(levels.count) * 0.35
            let barWidth = span / CGFloat(levels.count) - gap
            for (index, level) in levels.enumerated() {
                let height = max(barWidth, CGFloat(level) * size.height * (artwork == nil ? 0.5 : 0.22))
                let x = (size.width - span) / 2 + CGFloat(index) * (barWidth + gap)
                let bar = CGRect(x: x, y: baseline - (artwork == nil ? height / 2 : 0), width: barWidth, height: height)
                context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
                context.setFillColor(style.accent.withAlpha(0.55 + Double(level) * 0.45).cgColor)
                context.fillPath()
            }
        case .wave:
            guard wave.count > 1 else { break }
            let midY = artwork == nil ? center.y : size.height * 0.2
            let step = max(1, wave.count / 400)
            context.setStrokeColor(accent)
            context.setLineWidth(size.width * 0.006)
            context.setLineJoin(.round)
            context.beginPath()
            for (offset, sampleIndex) in stride(from: 0, to: wave.count, by: step).enumerated() {
                let x = size.width * 0.08 + CGFloat(offset * step) / CGFloat(wave.count) * size.width * 0.84
                let y = midY + CGFloat(wave[sampleIndex]) * size.height * 0.3
                offset == 0 ? context.move(to: CGPoint(x: x, y: y)) : context.addLine(to: CGPoint(x: x, y: y))
            }
            context.strokePath()
        case .pulse:
            let base = min(size.width, size.height) * 0.22
            for ring in 0..<4 {
                let radius = base * (1 + CGFloat(ring) * 0.35) * (1 + energy * 0.5)
                context.setStrokeColor(style.accent.withAlpha(0.7 - Double(ring) * 0.15).cgColor)
                context.setLineWidth(size.width * 0.008)
                context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            if artwork == nil {
                let radius = base * (0.8 + energy * 0.6)
                context.setFillColor(accent)
                context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
        }
    }
}
