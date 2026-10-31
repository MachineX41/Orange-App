@preconcurrency import AVFoundation
import CoreImage
import Foundation
import ImageIO

public struct VideoInfo: Sendable, Equatable {
    public var duration: Double
    /// Upright display size.
    public var size: CGSize
    public var fps: Double
    public var hasVideo: Bool
    public var hasAudio: Bool
}

public enum VideoQuality: String, CaseIterable, Codable, Sendable {
    case small, balanced, high

    var preset: String {
        switch self {
        case .small: AVAssetExportPreset960x540
        case .balanced: AVAssetExportPresetHEVC1920x1080
        case .high: AVAssetExportPresetHEVCHighestQuality
        }
    }
}

public enum VideoEditor {
    // MARK: Basics

    public static func fileType(for ext: String) -> AVFileType {
        switch ext.lowercased() {
        case "mov", "qt": .mov
        case "m4v": .m4v
        case "m4a": .m4a
        case "wav": .wav
        case "aif", "aiff": .aiff
        case "caf": .caf
        default: .mp4
        }
    }

    public static func info(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio)
        var size = CGSize.zero
        var fps = 0.0
        if let video {
            let (natural, transform, rate) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate)
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            size = CGSize(width: abs(rect.width), height: abs(rect.height))
            fps = Double(rate)
        }
        return VideoInfo(duration: duration.isFinite ? duration : 0, size: size, fps: fps, hasVideo: video != nil, hasAudio: !audio.isEmpty)
    }

    static func destination(for source: URL, suffix: String?, ext: String) -> URL {
        UniqueDestination.url(
            in: OutputLocation.directory(beside: source),
            baseName: OutputLocation.baseName(source, suffix: suffix),
            extension: ext
        )
    }

    static func outputExtension(for source: URL) -> String {
        let ext = source.pathExtension.lowercased()
        return ["mov", "mp4", "m4v"].contains(ext) ? ext : "mp4"
    }

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    static func range(_ range: ClosedRange<Double>) -> CMTimeRange {
        CMTimeRange(start: time(range.lowerBound), end: time(range.upperBound))
    }

    public static func run(
        _ session: AVAssetExportSession,
        to url: URL,
        type: AVFileType,
        progress: ProgressHandler?
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let monitor = Task {
            for await state in session.states(updateInterval: 0.15) {
                if case .exporting(let value) = state {
                    progress?(value.fractionCompleted)
                }
            }
        }
        defer { monitor.cancel() }
        do {
            try await withTaskCancellationHandler {
                try await session.export(to: url, as: type)
            } onCancel: {
                session.cancelExport()
            }
            progress?(1)
        } catch {
            try? FileManager.default.removeItem(at: url)
            if Task.isCancelled { throw OrangeError.cancelled }
            throw OrangeError.toolFailed(error.localizedDescription)
        }
    }

    static func export(
        _ asset: AVAsset,
        preset: String,
        to url: URL,
        timeRange: CMTimeRange? = nil,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        pitch: AVAudioTimePitchAlgorithm? = nil,
        progress: ProgressHandler?
    ) async throws {
        let type = fileType(for: url.pathExtension)
        var chosen = preset
        if !(await AVAssetExportSession.compatibility(ofExportPreset: chosen, with: asset, outputFileType: type)) {
            chosen = AVAssetExportPresetHighestQuality
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: chosen) else {
            throw OrangeError.unsupported(url.pathExtension.uppercased())
        }
        if let timeRange { session.timeRange = timeRange }
        if let videoComposition { session.videoComposition = videoComposition }
        if let audioMix { session.audioMix = audioMix }
        if let pitch { session.audioTimePitchAlgorithm = pitch }
        session.shouldOptimizeForNetworkUse = type != .mov
        try await run(session, to: url, type: type, progress: progress)
    }

    // MARK: Conversion

    public static func convert(_ url: URL, to target: ConvertTarget, progress: ProgressHandler?) async throws -> URL {
        switch target {
        case .gif:
            return try await GIFMaker.make(from: url, progress: progress)
        case .m4a:
            let output = destination(for: url, suffix: nil, ext: "m4a")
            try await export(AVURLAsset(url: url), preset: AVAssetExportPresetAppleM4A, to: output, progress: progress)
            return output
        case .mp4, .mov, .m4v:
            let output = destination(for: url, suffix: nil, ext: target.fileExtension)
            try await export(AVURLAsset(url: url), preset: AVAssetExportPresetPassthrough, to: output, progress: progress)
            return output
        default:
            throw OrangeError.unsupported(target.rawValue.uppercased())
        }
    }

    // MARK: Editing

    public static func trim(_ url: URL, range keep: ClosedRange<Double>, progress: ProgressHandler?) async throws -> URL {
        let output = destination(for: url, suffix: Lang.t("Trimmed", "Kırpılmış"), ext: outputExtension(for: url))
        try await export(AVURLAsset(url: url), preset: AVAssetExportPresetHighestQuality, to: output, timeRange: range(keep), progress: progress)
        return output
    }

    public static func split(_ url: URL, at points: [Double], progress: ProgressHandler?) async throws -> [URL] {
        let duration = try await info(url).duration
        let cuts = ([0] + points.filter { $0 > 0.05 && $0 < duration - 0.05 }.sorted() + [duration])
        guard cuts.count > 2 else { throw OrangeError.nothingFound }
        let base = url.deletingPathExtension().lastPathComponent
        let folder = UniqueDestination.folder(in: OutputLocation.directory(beside: url), baseName: "\(base) \(Lang.t("Parts", "Parçalar"))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let segments = Array(zip(cuts, cuts.dropFirst()))
        for (index, segment) in segments.enumerated() {
            let output = UniqueDestination.url(in: folder, baseName: "\(base) \(index + 1)", extension: outputExtension(for: url))
            try await export(AVURLAsset(url: url), preset: AVAssetExportPresetHighestQuality, to: output, timeRange: range(segment.0...segment.1)) { value in
                progress?((Double(index) + value) / Double(segments.count))
            }
        }
        return [folder]
    }

    public static func mute(_ url: URL, progress: ProgressHandler?) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        guard let source = try await asset.loadTracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw OrangeError.unsupported(url.pathExtension)
        }
        let (timeRange, transform) = try await source.load(.timeRange, .preferredTransform)
        try track.insertTimeRange(timeRange, of: source, at: .zero)
        track.preferredTransform = transform
        let output = destination(for: url, suffix: Lang.t("Muted", "Sessiz"), ext: outputExtension(for: url))
        try await export(composition, preset: AVAssetExportPresetPassthrough, to: output, progress: progress)
        return output
    }

    public static func changeSpeed(_ url: URL, factor: Double, progress: ProgressHandler?) async throws -> URL {
        guard factor > 0 else { throw OrangeError.unsupported("speed") }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        let full = CMTimeRange(start: .zero, duration: duration)
        for type in [AVMediaType.video, .audio] {
            guard let source = try await asset.loadTracks(withMediaType: type).first,
                  let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try track.insertTimeRange(full, of: source, at: .zero)
            if type == .video { track.preferredTransform = try await source.load(.preferredTransform) }
        }
        composition.scaleTimeRange(full, toDuration: CMTimeMultiplyByFloat64(duration, multiplier: 1 / factor))
        let label = String(format: "%gx", factor)
        let output = destination(for: url, suffix: label, ext: outputExtension(for: url))
        try await export(composition, preset: AVAssetExportPresetHighestQuality, to: output, pitch: .spectral, progress: progress)
        return output
    }

    static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, (size.width / 2).rounded(.down) * 2), height: max(2, (size.height / 2).rounded(.down) * 2))
    }

    public static func crop(_ url: URL, normalized: CGRect, progress: ProgressHandler?) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let size = try await info(url).size
        let pixels = CropMath.pixelRect(normalizedTopLeft: normalized, imageSize: size).integral
            .intersection(CGRect(origin: .zero, size: size))
        let render = evenSize(pixels.size)
        let rect = CGRect(origin: pixels.origin, size: render)
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let image = request.sourceImage.cropped(to: rect)
                .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            request.finish(with: image, context: nil)
        }
        composition.renderSize = render
        let output = destination(for: url, suffix: Lang.t("Cropped", "Kırpılmış"), ext: outputExtension(for: url))
        try await export(asset, preset: AVAssetExportPresetHighestQuality, to: output, videoComposition: composition, progress: progress)
        return output
    }

    public static func redact(_ url: URL, regions: [CGRect], style: RedactStyle, progress: ProgressHandler?) async throws -> URL {
        guard !regions.isEmpty else { throw OrangeError.empty }
        let asset = AVURLAsset(url: url)
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let source = request.sourceImage
            let shifted = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
            request.finish(with: Redactor.apply(regions, style: style, to: shifted), context: nil)
        }
        let output = destination(for: url, suffix: Lang.t("Redacted", "Gizlenmiş"), ext: outputExtension(for: url))
        try await export(asset, preset: AVAssetExportPresetHighestQuality, to: output, videoComposition: composition, progress: progress)
        return output
    }

    public static func compress(_ url: URL, quality: VideoQuality, progress: ProgressHandler?) async throws -> URL {
        let output = destination(for: url, suffix: Lang.t("Compressed", "Sıkıştırılmış"), ext: "mp4")
        try await export(AVURLAsset(url: url), preset: quality.preset, to: output, progress: progress)
        let before = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let after = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if before > 0, after >= before {
            try? FileManager.default.removeItem(at: output)
            throw OrangeError.notSmaller
        }
        return output
    }

    public static func join(_ urls: [URL], progress: ProgressHandler?) async throws -> URL {
        guard urls.count >= 2 else { throw OrangeError.unsupported("join") }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw OrangeError.writeFailed("join")
        }
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        var renderSize = CGSize.zero
        var cursor = CMTime.zero
        var frameRate: Float = 30
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let span = CMTimeRange(start: .zero, duration: duration)
            if let source = try await asset.loadTracks(withMediaType: .video).first {
                let (natural, transform, rate) = try await source.load(.naturalSize, .preferredTransform, .nominalFrameRate)
                let upright = CGRect(origin: .zero, size: natural).applying(transform)
                let size = CGSize(width: abs(upright.width), height: abs(upright.height))
                if renderSize == .zero {
                    renderSize = evenSize(size)
                    frameRate = max(rate, 24)
                }
                try videoTrack.insertTimeRange(span, of: source, at: cursor)
                let scale = min(renderSize.width / size.width, renderSize.height / size.height)
                let fitted = CGSize(width: size.width * scale, height: size.height * scale)
                let fix = CGAffineTransform(translationX: -upright.minX, y: -upright.minY)
                let placed = transform.concatenating(fix)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(
                        translationX: (renderSize.width - fitted.width) / 2,
                        y: (renderSize.height - fitted.height) / 2
                    ))
                layer.setTransform(placed, at: cursor)
            }
            if let source = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(span, of: source, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
        }
        if audioTrack.segments.isEmpty { composition.removeTrack(audioTrack) }
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded()))
        videoComposition.instructions = [instruction]
        let output = destination(for: urls[0], suffix: Lang.t("Joined", "Birleşik"), ext: "mp4")
        try await export(composition, preset: AVAssetExportPresetHighestQuality, to: output, videoComposition: videoComposition, progress: progress)
        return output
    }

    // MARK: Frames

    static func generator(for url: URL, maxSide: CGFloat? = nil, exact: Bool) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        if let maxSide { generator.maximumSize = CGSize(width: maxSide, height: maxSide) }
        if exact {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        }
        return generator
    }

    public static func frame(_ url: URL, at seconds: Double, maxSide: CGFloat? = nil) async throws -> CGImage {
        try await generator(for: url, maxSide: maxSide, exact: true).image(at: time(seconds)).image
    }

    public static func thumbnails(_ url: URL, count: Int, maxSide: CGFloat) async -> [CGImage] {
        guard count > 0, let duration = try? await info(url).duration, duration > 0 else { return [] }
        let times = (0..<count).map { time(duration * (Double($0) + 0.5) / Double(count)) }
        var images: [CGImage] = []
        for await result in generator(for: url, maxSide: maxSide, exact: false).images(for: times) {
            if let image = try? result.image { images.append(image) }
        }
        return images
    }

    public static func exportFrames(
        _ url: URL,
        times: [Double],
        format: ConvertTarget,
        progress: ProgressHandler?
    ) async throws -> [URL] {
        guard !times.isEmpty else { throw OrangeError.empty }
        let base = url.deletingPathExtension().lastPathComponent
        let parent = OutputLocation.directory(beside: url)
        let folder = times.count > 1 ? UniqueDestination.folder(in: parent, baseName: "\(base) \(Lang.t("Frames", "Kareler"))") : parent
        if times.count > 1 { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        var outputs: [URL] = []
        let generator = generator(for: url, exact: true)
        for (index, seconds) in times.enumerated() {
            try Task.checkCancellation()
            let image = try await generator.image(at: time(seconds)).image
            let stamp = Timecode.string(seconds, fraction: true).replacingOccurrences(of: ":", with: ".")
            let output = UniqueDestination.url(in: folder, baseName: "\(base) \(stamp)", extension: format.fileExtension)
            try ImageEngine.write(image, to: output, as: format, quality: 0.92)
            outputs.append(output)
            progress?(Double(index + 1) / Double(times.count))
        }
        return times.count > 1 ? [folder] : outputs
    }
}

public enum GIFMaker {
    public static func make(
        from url: URL,
        range: ClosedRange<Double>? = nil,
        fps: Double = 12,
        maxWidth: CGFloat = 640,
        progress: ProgressHandler?
    ) async throws -> URL {
        let info = try await VideoEditor.info(url)
        guard info.hasVideo else { throw OrangeError.unsupported("GIF") }
        let span = range ?? 0...min(info.duration, 30)
        let count = max(1, Int((span.upperBound - span.lowerBound) * fps))
        let times = (0..<count).map { VideoEditor.time(span.lowerBound + Double($0) / fps) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 4)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)

        let output = VideoEditor.destination(for: url, suffix: nil, ext: "gif")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, "com.compuserve.gif" as CFString, count, nil) else {
            throw OrangeError.writeFailed("GIF")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / fps]
        ] as CFDictionary
        var written = 0
        for await result in generator.images(for: times) {
            if Task.isCancelled { throw OrangeError.cancelled }
            guard let image = try? result.image else { continue }
            CGImageDestinationAddImage(destination, image, frameProperties)
            written += 1
            progress?(Double(written) / Double(count))
        }
        guard written > 0, CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw OrangeError.writeFailed("GIF")
        }
        return output
    }
}
