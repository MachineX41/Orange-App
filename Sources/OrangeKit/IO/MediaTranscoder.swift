import AVFoundation
import Foundation

public struct MediaTranscoder: Sendable {
    public init() {}

    public func export(source: URL, target: ConvertTarget, directory: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let preset: String
        let fileType: AVFileType
        switch target {
        case .mp4:
            preset = AVAssetExportPresetHighestQuality
            fileType = .mp4
        case .mov:
            preset = AVAssetExportPresetHighestQuality
            fileType = .mov
        case .m4a:
            preset = AVAssetExportPresetAppleM4A
            fileType = .m4a
        default:
            throw OrangeError.unsupported(target.rawValue)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw OrangeError.unsupported(source.lastPathComponent)
        }
        let supported = session.supportedFileTypes
        guard supported.contains(fileType) else {
            throw OrangeError.unsupported(source.lastPathComponent)
        }
        let destination = UniqueDestination.url(
            in: directory,
            baseName: source.deletingPathExtension().lastPathComponent,
            extension: target.fileExtension
        )
        session.outputURL = destination
        session.outputFileType = fileType
        try await export(session)
        return destination
    }

    private func export(_ session: AVAssetExportSession) async throws {
        final class SessionBox: @unchecked Sendable {
            let session: AVAssetExportSession
            init(_ session: AVAssetExportSession) { self.session = session }
        }
        let box = SessionBox(session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.session.exportAsynchronously {
                switch box.session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: OrangeError.cancelled)
                default:
                    let message = box.session.error?.localizedDescription ?? "media"
                    continuation.resume(throwing: OrangeError.writeFailed(message))
                }
            }
        }
    }
}
