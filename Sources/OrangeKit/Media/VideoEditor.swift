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
            try await transcode(url, to: output, progress: progress)
            return output
        default:
            throw OrangeError.unsupported(target.rawValue.uppercased())
        }
    }

    /// Original frame size, HEVC when the Mac can encode it, at a rate that stays visually clean and under the source.
    /// A container copy keeps every bit and therefore the same file size. This re-encode is what actually shrinks a .mov.
    static func transcode(_ url: URL, to output: URL, progress: ProgressHandler?) async throws {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw OrangeError.unsupported(url.pathExtension.uppercased())
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let (natural, transform, nominalRate) = try await videoTrack.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let dataRate = try await videoTrack.load(.estimatedDataRate)
        let duration = try await asset.load(.duration).seconds
        let description = try await videoTrack.load(.formatDescriptions).first
        let size = evenSize(CGSize(width: abs(natural.width), height: abs(natural.height)))
        guard size.width >= 2, size.height >= 2 else { throw OrangeError.unsupported(url.pathExtension.uppercased()) }

        let fps = nominalRate > 1 ? Double(nominalRate) : 30
        var sourceRate = Double(dataRate)
        if sourceRate < 1, duration > 0, let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            sourceRate = Double(bytes) * 8 / duration
        }
        let pixels = size.width * size.height
        let color = description.flatMap(colorProperties(for:))
        let tenBit = description.map(wantsTenBit) ?? false
        let fullRange = description.map(isFullRange) ?? false
        let audio = await audioPlan(for: audioTrack)

        let attempts: [(OSType, AVVideoCodecType, Bool)] = tenBit
            ? [
                (pixelFormat(tenBit: true, fullRange: fullRange), .hevc, true),
                (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, .hevc, true),
                (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, .h264, false),
            ]
            : [
                (pixelFormat(tenBit: false, fullRange: fullRange), .hevc, true),
                (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, .h264, false),
            ]

        var last = output.lastPathComponent
        for (pixel, codec, hevc) in attempts {
            let bitrate = compactVideoBitrate(pixels: pixels, fps: fps, sourceBitsPerSecond: sourceRate, hevc: hevc)
            do {
                try await write(
                    asset: asset,
                    videoTrack: videoTrack,
                    audioTrack: audioTrack,
                    audio: audio,
                    to: output,
                    size: size,
                    fps: fps,
                    transform: transform,
                    pixelFormat: pixel,
                    codec: codec,
                    bitrate: bitrate,
                    color: color,
                    duration: duration,
                    progress: progress
                )
                return
            } catch TranscodeFailure.setup(let message) {
                try? FileManager.default.removeItem(at: output)
                last = message
            } catch TranscodeFailure.encode(let error) {
                try? FileManager.default.removeItem(at: output)
                throw error
            } catch {
                try? FileManager.default.removeItem(at: output)
                throw error
            }
        }
        throw OrangeError.toolFailed(last)
    }

    /// Bits per second for a same-resolution encode that still looks clean.
    /// A bloated master lands on the transparent rate. A file that is already efficient only loses a little, so it shrinks without being chewed up.
    static func compactVideoBitrate(pixels: Double, fps: Double, sourceBitsPerSecond: Double, hevc: Bool) -> Int {
        let frames = max(fps, 1)
        let clean = pixels * frames * (hevc ? 0.12 : 0.20)
        let source = max(sourceBitsPerSecond, 0)
        let target = source > clean * 1.25 ? clean : (source > 1_000 ? min(source * 0.80, clean) : clean)
        if source > 1_000 {
            return max(Int(min(target, source * 0.92).rounded()), 1)
        }
        return Int(max(target, 250_000).rounded())
    }

    private struct AudioPlan {
        var passthrough: Bool
        var sampleRate: Double
        var channels: Int
    }

    private enum TranscodeFailure: Error {
        case setup(String)
        case encode(Error)
    }

    private static func audioPlan(for track: AVAssetTrack?) async -> AudioPlan? {
        guard let track else { return nil }
        guard let description = try? await track.load(.formatDescriptions).first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            return AudioPlan(passthrough: false, sampleRate: 48_000, channels: 2)
        }
        let channels = min(max(Int(basic.mChannelsPerFrame), 1), 2)
        let rate = basic.mSampleRate > 0 ? basic.mSampleRate : 48_000
        let standard = [8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000]
        let sampleRate = standard.contains(Int(rate.rounded())) ? rate : 48_000
        return AudioPlan(passthrough: basic.mFormatID == kAudioFormatMPEG4AAC, sampleRate: sampleRate, channels: channels)
    }

    private static func pixelFormat(tenBit: Bool, fullRange: Bool) -> OSType {
        switch (tenBit, fullRange) {
        case (true, true): kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
        case (true, false): kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        case (false, true): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        case (false, false): kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
    }

    private static func wantsTenBit(_ description: CMFormatDescription) -> Bool {
        guard let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] else { return false }
        if let bits = extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? NSNumber, bits.intValue > 8 {
            return true
        }
        let transfer = extensions[kCVImageBufferTransferFunctionKey as String] as? String
        return transfer == (AVVideoTransferFunction_SMPTE_ST_2084_PQ as String)
            || transfer == (AVVideoTransferFunction_ITU_R_2100_HLG as String)
    }

    private static func isFullRange(_ description: CMFormatDescription) -> Bool {
        guard let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] else { return false }
        return (extensions[kCMFormatDescriptionExtension_FullRangeVideo as String] as? NSNumber)?.boolValue == true
    }

    private static func colorProperties(for description: CMFormatDescription) -> [String: Any]? {
        guard let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] else { return nil }
        var color: [String: Any] = [:]
        if let value = extensions[kCVImageBufferColorPrimariesKey as String] { color[AVVideoColorPrimariesKey] = value }
        if let value = extensions[kCVImageBufferTransferFunctionKey as String] { color[AVVideoTransferFunctionKey] = value }
        if let value = extensions[kCVImageBufferYCbCrMatrixKey as String] { color[AVVideoYCbCrMatrixKey] = value }
        return color.isEmpty ? nil : color
    }

    private static func write(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack?,
        audio: AudioPlan?,
        to output: URL,
        size: CGSize,
        fps: Double,
        transform: CGAffineTransform,
        pixelFormat: OSType,
        codec: AVVideoCodecType,
        bitrate: Int,
        color: [String: Any]?,
        duration: Double,
        progress: ProgressHandler?
    ) async throws {
        try? FileManager.default.removeItem(at: output)
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw TranscodeFailure.setup(output.lastPathComponent) }
        reader.add(videoOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: fileType(for: output.pathExtension))
        writer.shouldOptimizeForNetworkUse = output.pathExtension.lowercased() != "mov"
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: max(Int(fps.rounded()), 1),
            AVVideoMaxKeyFrameIntervalKey: max(Int(fps.rounded()) * 2, 2),
            AVVideoAllowFrameReorderingKey: true,
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: compression,
        ]
        if let color { videoSettings[AVVideoColorPropertiesKey] = color }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else { throw TranscodeFailure.setup(output.lastPathComponent) }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack, let audio {
            let attached = attachAudio(audio, track: audioTrack, reader: reader, writer: writer)
            audioOutput = attached?.output
            audioInput = attached?.input
        }

        guard writer.startWriting() else {
            throw TranscodeFailure.setup(writer.error?.localizedDescription ?? output.lastPathComponent)
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            writer.cancelWriting()
            throw TranscodeFailure.setup(reader.error?.localizedDescription ?? output.lastPathComponent)
        }

        var videoDone = false
        var audioDone = audioInput == nil
        var reported = 0.0
        var producedVideo = false
        while !videoDone || !audioDone {
            if Task.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                throw OrangeError.cancelled
            }
            var wrote = false
            if !videoDone, videoInput.isReadyForMoreMediaData {
                if let sample = videoOutput.copyNextSampleBuffer() {
                    guard videoInput.append(sample) else {
                        reader.cancelReading()
                        throw TranscodeFailure.encode(OrangeError.toolFailed(writer.error?.localizedDescription ?? output.lastPathComponent))
                    }
                    producedVideo = true
                    if duration > 0 {
                        let fraction = min(max(CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration, 0), 0.99)
                        if fraction - reported >= 0.01 {
                            reported = fraction
                            progress?(fraction)
                        }
                    }
                } else if reader.status == .failed {
                    writer.cancelWriting()
                    throw TranscodeFailure.encode(OrangeError.toolFailed(reader.error?.localizedDescription ?? output.lastPathComponent))
                } else {
                    videoInput.markAsFinished()
                    videoDone = true
                }
                wrote = true
            }
            if !audioDone, let audioInput, let audioOutput, audioInput.isReadyForMoreMediaData {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else {
                        reader.cancelReading()
                        throw TranscodeFailure.encode(OrangeError.toolFailed(writer.error?.localizedDescription ?? output.lastPathComponent))
                    }
                } else if reader.status == .failed {
                    writer.cancelWriting()
                    throw TranscodeFailure.encode(OrangeError.toolFailed(reader.error?.localizedDescription ?? output.lastPathComponent))
                } else {
                    audioInput.markAsFinished()
                    audioDone = true
                }
                wrote = true
            }
            if !wrote { try await Task.sleep(for: .milliseconds(2)) }
        }
        guard producedVideo else {
            writer.cancelWriting()
            throw TranscodeFailure.encode(OrangeError.unreadable(output.lastPathComponent))
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TranscodeFailure.encode(OrangeError.toolFailed(writer.error?.localizedDescription ?? output.lastPathComponent))
        }
        progress?(1)
    }

    private static func attachAudio(
        _ audio: AudioPlan,
        track: AVAssetTrack,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) -> (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)? {
        func pair(passthrough: Bool) -> (AVAssetReaderTrackOutput, AVAssetWriterInput) {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: passthrough ? nil : pcmSettings(audio))
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: passthrough ? nil : aacSettings(audio))
            input.expectsMediaDataInRealTime = false
            return (output, input)
        }
        var (output, input) = pair(passthrough: audio.passthrough)
        if !reader.canAdd(output) || !writer.canAdd(input), audio.passthrough {
            (output, input) = pair(passthrough: false)
        }
        guard reader.canAdd(output), writer.canAdd(input) else { return nil }
        reader.add(output)
        writer.add(input)
        return (output, input)
    }

    private static func pcmSettings(_ audio: AudioPlan) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: audio.channels,
        ]
    }

    private static func aacSettings(_ audio: AudioPlan) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: audio.channels,
            AVEncoderBitRateKey: audio.channels > 1 ? 256_000 : 160_000,
        ]
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
