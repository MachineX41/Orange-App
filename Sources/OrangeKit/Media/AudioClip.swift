@preconcurrency import AVFoundation
import Accelerate
import Foundation

/// Decoded PCM audio held in memory as one Float array per channel.
public struct AudioClip: Sendable {
    public var sampleRate: Double
    public var channels: [[Float]]

    public init(sampleRate: Double, channels: [[Float]]) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var frameCount: Int { channels.first?.count ?? 0 }
    public var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }
    public var channelCount: Int { channels.count }

    // MARK: IO

    public static func load(_ url: URL) async throws -> AudioClip {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw OrangeError.unsupported(url.pathExtension.uppercased())
        }
        var sourceChannels = 2
        var sourceRate = 44_100.0
        if let description = try await track.load(.formatDescriptions).first,
           let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            sourceChannels = Int(basic.mChannelsPerFrame)
            if basic.mSampleRate > 0 { sourceRate = basic.mSampleRate }
        }
        let channelCount = min(max(sourceChannels, 1), 2)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sourceRate,
            AVNumberOfChannelsKey: channelCount
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw OrangeError.unsupported(url.pathExtension.uppercased()) }
        reader.add(output)
        guard reader.startReading() else { throw OrangeError.unreadable(url.lastPathComponent) }

        var interleaved: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw OrangeError.cancelled
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            interleaved.append(contentsOf: chunk)
        }
        guard reader.status == .completed else { throw OrangeError.unreadable(url.lastPathComponent) }
        let frames = interleaved.count / channelCount
        var channels = [[Float]](repeating: [Float](repeating: 0, count: frames), count: channelCount)
        interleaved.withUnsafeBufferPointer { source in
            for channel in 0..<channelCount {
                channels[channel].withUnsafeMutableBufferPointer { target in
                    for frame in 0..<frames {
                        target[frame] = source[frame * channelCount + channel]
                    }
                }
            }
        }
        return AudioClip(sampleRate: sourceRate, channels: channels)
    }

    public func write(to url: URL) throws {
        guard frameCount > 0 else { throw OrangeError.empty }
        let ext = url.pathExtension.lowercased()
        let count = channelCount
        var settings: [String: Any] = [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: count
        ]
        switch ext {
        case "wav":
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
        case "aif", "aiff":
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = true
        case "caf":
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 32
            settings[AVLinearPCMIsFloatKey] = true
        default:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = count == 1 ? 128_000 : 256_000
            settings[AVSampleRateKey] = min(max(sampleRate, 8_000), 48_000)
        }
        try? FileManager.default.removeItem(at: url)
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = file.processingFormat
            let chunk = 32_768
            var offset = 0
            while offset < frameCount {
                let length = min(chunk, frameCount - offset)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)),
                      let data = buffer.floatChannelData else { throw OrangeError.writeFailed(url.lastPathComponent) }
                buffer.frameLength = AVAudioFrameCount(length)
                for channel in 0..<Int(format.channelCount) {
                    let source = channels[min(channel, count - 1)]
                    source.withUnsafeBufferPointer { pointer in
                        data[channel].update(from: pointer.baseAddress! + offset, count: length)
                    }
                }
                try file.write(from: buffer)
                offset += length
            }
        } catch let error as OrangeError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
    }

    // MARK: Processing

    func frame(_ seconds: Double) -> Int {
        min(max(0, Int((seconds * sampleRate).rounded())), frameCount)
    }

    public func trimmed(_ start: Double, _ end: Double) -> AudioClip {
        let lower = frame(start)
        let upper = max(lower, frame(end))
        return AudioClip(sampleRate: sampleRate, channels: channels.map { Array($0[lower..<upper]) })
    }

    /// Start and end of the audible region in seconds.
    public func silenceBounds(thresholdDB: Double = -45) -> ClosedRange<Double> {
        let threshold = Float(pow(10, thresholdDB / 20))
        let mixed = mono()
        let window = max(1, Int(sampleRate * 0.01))
        var first: Int?
        var last: Int?
        var index = 0
        while index < mixed.count {
            let end = min(index + window, mixed.count)
            let peak = mixed[index..<end].withUnsafeBufferPointer { vDSP.maximumMagnitude($0) }
            if peak >= threshold {
                if first == nil { first = index }
                last = end
            }
            index = end
        }
        guard let first, let last else { return 0...duration }
        return Double(first) / sampleRate...Double(last) / sampleRate
    }

    public func mono() -> [Float] {
        guard channels.count > 1 else { return channels.first ?? [] }
        var sum = vDSP.add(channels[0], channels[1])
        vDSP.multiply(0.5, sum, result: &sum)
        return sum
    }

    public func remixed(toMono: Bool, gains: [Double]) -> AudioClip {
        let left = Float(gains.first ?? 1)
        let right = Float(gains.count > 1 ? gains[1] : gains.first ?? 1)
        if toMono {
            return AudioClip(sampleRate: sampleRate, channels: [vDSP.multiply(left, mono())])
        }
        let l = channels.first ?? []
        let r = channels.count > 1 ? channels[1] : l
        return AudioClip(sampleRate: sampleRate, channels: [vDSP.multiply(left, l), vDSP.multiply(right, r)])
    }

    public var peak: Float {
        channels.map { $0.isEmpty ? 0 : vDSP.maximumMagnitude($0) }.max() ?? 0
    }

    public var rms: Float {
        let values = channels.map { $0.isEmpty ? 0 : vDSP.rootMeanSquare($0) }
        return values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }

    public static func decibels(_ linear: Float) -> Double {
        linear > 0 ? 20 * log10(Double(linear)) : -120
    }

    public func gained(_ db: Double) -> AudioClip {
        let factor = Float(pow(10, db / 20))
        return AudioClip(sampleRate: sampleRate, channels: channels.map { vDSP.clip(vDSP.multiply(factor, $0), to: -1...1) })
    }

    public enum Normalization: String, CaseIterable, Sendable {
        case peak, loudness
    }

    /// Peak mode targets the given dBFS peak; loudness mode targets an RMS level and limits peaks at -1 dBFS.
    public func normalized(_ mode: Normalization, target db: Double) -> AudioClip {
        switch mode {
        case .peak:
            let current = AudioClip.decibels(peak)
            return gained(db - current)
        case .loudness:
            let current = AudioClip.decibels(rms)
            let headroom = -1 - AudioClip.decibels(peak)
            return gained(min(db - current, headroom))
        }
    }

    public func bleeped(_ ranges: [ClosedRange<Double>], tone: Bool, frequency: Double = 1_000) -> AudioClip {
        var output = channels
        let level = Float(0.35)
        for range in ranges {
            let lower = frame(range.lowerBound)
            let upper = frame(range.upperBound)
            guard upper > lower else { continue }
            let fade = min(Int(sampleRate * 0.004), (upper - lower) / 2)
            for channel in output.indices {
                output[channel].withUnsafeMutableBufferPointer { samples in
                    for index in lower..<upper {
                        let position = index - lower
                        let edge = min(position, upper - 1 - index)
                        let envelope = fade > 0 ? min(1, Float(edge) / Float(fade)) : 1
                        let value = tone ? level * Float(sin(2 * .pi * frequency * Double(index) / sampleRate)) : 0
                        samples[index] = samples[index] * (1 - envelope) + value * envelope
                    }
                }
            }
        }
        return AudioClip(sampleRate: sampleRate, channels: output)
    }

    /// Absolute peak per bucket of the mixed signal, 0...1.
    public func peaks(buckets: Int) -> [Float] {
        let mixed = mono()
        guard buckets > 0, !mixed.isEmpty else { return [] }
        let size = max(1, mixed.count / buckets)
        return mixed.withUnsafeBufferPointer { pointer in
            (0..<buckets).map { bucket in
                let start = min(bucket * size, mixed.count)
                let end = min(start + size, mixed.count)
                guard end > start else { return 0 }
                return min(1, vDSP.maximumMagnitude(UnsafeBufferPointer(rebasing: pointer[start..<end])))
            }
        }
    }

    public func channelPeaks(buckets: Int) -> [[Float]] {
        channels.map { AudioClip(sampleRate: sampleRate, channels: [$0]).peaks(buckets: buckets) }
    }
}

public enum AudioEngine {
    static func destination(for source: URL, suffix: String?, ext: String) -> URL {
        UniqueDestination.url(
            in: OutputLocation.directory(beside: source),
            baseName: OutputLocation.baseName(source, suffix: suffix),
            extension: ext
        )
    }

    static func outputExtension(for source: URL) -> String {
        let ext = source.pathExtension.lowercased()
        return ["m4a", "wav", "aif", "aiff", "caf"].contains(ext) ? ext : "m4a"
    }

    public static func save(_ clip: AudioClip, from source: URL, suffix: String?, ext: String? = nil) throws -> URL {
        let output = destination(for: source, suffix: suffix, ext: ext ?? outputExtension(for: source))
        try clip.write(to: output)
        return output
    }

    public static func convert(_ url: URL, to target: ConvertTarget, progress: ProgressHandler?) async throws -> URL {
        progress?(0.1)
        let clip = try await AudioClip.load(url)
        progress?(0.6)
        let output = try save(clip, from: url, suffix: nil, ext: target.fileExtension)
        progress?(1)
        return output
    }
}
