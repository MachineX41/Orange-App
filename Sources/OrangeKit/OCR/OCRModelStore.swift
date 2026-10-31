import CryptoKit
import Foundation

/// Tracks which model pairs are verified on disk. Root defaults to
/// `~/Library/Application Support/Orange/Models`; layouts with a matching
/// verified manifest and unmodified size/mtime are usable without rehashing.
public actor OCRModelStore {
    public enum Status: Sendable {
        case notInstalled
        case installed
    }

    public struct VerifiedManifest: Codable, Sendable {
        public var modelID: String
        public var revision: String
        public var artifacts: [ArtifactRecord]

        public struct ArtifactRecord: Codable, Sendable {
            public var filename: String
            public var byteCount: Int64
            public var sha256: String
        }
    }

    public var root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.root = base.appendingPathComponent("Orange/Models", isDirectory: true)
        }
    }

    public func installedDirectory(for id: OCRModelID, revision: String) -> URL {
        root.appendingPathComponent("\(id.rawValue)/\(revision)", isDirectory: true)
    }

    public func stagingDirectory(for id: OCRModelID, revision: String) -> URL {
        root.appendingPathComponent(".staging/\(id.rawValue)/\(revision)", isDirectory: true)
    }

    public func manifestURL(for id: OCRModelID, revision: String) -> URL {
        installedDirectory(for: id, revision: revision).appendingPathComponent("verified.json")
    }

    public func status(for entry: OCRModelEntry) -> Status {
        let directory = installedDirectory(for: entry.id, revision: entry.revision)
        guard let manifest = try? readManifest(for: entry) else { return .notInstalled }
        guard manifest.modelID == entry.id.rawValue, manifest.revision == entry.revision else { return .notInstalled }
        for record in manifest.artifacts {
            let url = directory.appendingPathComponent(record.filename)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize, Int64(size) == record.byteCount,
                  FileManager.default.fileExists(atPath: url.path)
            else { return .notInstalled }
        }
        // Entry artifacts must all be covered by the manifest.
        let manifestFiles = Set(manifest.artifacts.map(\.filename))
        for artifact in entry.artifacts where !manifestFiles.contains(artifact.filename) {
            return .notInstalled
        }
        return .installed
    }

    /// Full rehash when size/mtime changed or before first use.
    public func verifyInstalled(_ entry: OCRModelEntry) throws {
        let directory = installedDirectory(for: entry.id, revision: entry.revision)
        for artifact in entry.artifacts {
            let url = directory.appendingPathComponent(artifact.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OrangeError.unreadable(artifact.filename)
            }
            try verifyFile(url, expectedBytes: artifact.byteCount, expectedSHA256: artifact.sha256)
        }
        try writeVerifiedManifest(for: entry)
    }

    public func verifyStagedFile(_ url: URL, artifact: OCRModelArtifact) throws {
        try verifyFile(url, expectedBytes: artifact.byteCount, expectedSHA256: artifact.sha256)
        // GGUF magic check: "GGUF" little-endian.
        guard let handle = try? FileHandle(forReadingFrom: url),
              let prefix = try? handle.read(upToCount: 4)
        else { throw OrangeError.unreadable(artifact.filename) }
        try? handle.close()
        guard prefix.count == 4, prefix[prefix.startIndex] == 0x47, prefix[prefix.startIndex + 1] == 0x47,
              prefix[prefix.startIndex + 2] == 0x55, prefix[prefix.startIndex + 3] == 0x46
        else { throw OrangeError.unreadable(artifact.filename) }
    }

    public func promoteStaging(_ entry: OCRModelEntry) throws {
        let staging = stagingDirectory(for: entry.id, revision: entry.revision)
        let installed = installedDirectory(for: entry.id, revision: entry.revision)
        for artifact in entry.artifacts {
            let url = staging.appendingPathComponent(artifact.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OrangeError.unreadable(artifact.filename)
            }
        }
        let parent = installed.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: installed.path) {
            try FileManager.default.removeItem(at: installed)
        }
        try FileManager.default.moveItem(at: staging, to: installed)
        try writeVerifiedManifest(for: entry)
    }

    public func removeInstalled(_ entry: OCRModelEntry) throws {
        let directory = installedDirectory(for: entry.id, revision: entry.revision)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    public func removePartial(_ entry: OCRModelEntry) throws {
        let staging = stagingDirectory(for: entry.id, revision: entry.revision)
        if FileManager.default.fileExists(atPath: staging.path) {
            try FileManager.default.removeItem(at: staging)
        }
    }

    /// Rejects traversal and symlink escapes: resolved paths must stay under root.
    public func safeArtifactURL(entry: OCRModelEntry, filename: String) throws -> URL {
        guard entry.artifacts.contains(where: { $0.filename == filename }) else {
            throw OrangeError.unsupported(filename)
        }
        return try safeURL(installedDirectory(for: entry.id, revision: entry.revision).appendingPathComponent(filename))
    }

    public func safeStagingURL(entry: OCRModelEntry, filename: String) throws -> URL {
        guard entry.artifacts.contains(where: { $0.filename == filename }) else {
            throw OrangeError.unsupported(filename)
        }
        return try safeURL(stagingDirectory(for: entry.id, revision: entry.revision).appendingPathComponent(filename))
    }

    private func safeURL(_ url: URL) throws -> URL {
        let rootPath = root.standardized.path
        let resolved = url.resolvingSymlinksInPath().standardized.path
        guard resolved == rootPath || resolved.hasPrefix(rootPath + "/") else {
            throw OrangeError.unsafeArchive
        }
        // Also reject unresolved `..` tricks before they touch the filesystem.
        let raw = url.standardized.path
        guard raw == rootPath || raw.hasPrefix(rootPath + "/") else {
            throw OrangeError.unsafeArchive
        }
        return url
    }

    private func readManifest(for entry: OCRModelEntry) throws -> VerifiedManifest {
        let data = try Data(contentsOf: manifestURL(for: entry.id, revision: entry.revision))
        return try JSONDecoder().decode(VerifiedManifest.self, from: data)
    }

    private func writeVerifiedManifest(for entry: OCRModelEntry) throws {
        let manifest = VerifiedManifest(
            modelID: entry.id.rawValue,
            revision: entry.revision,
            artifacts: entry.artifacts.map {
                VerifiedManifest.ArtifactRecord(filename: $0.filename, byteCount: $0.byteCount, sha256: $0.sha256)
            }
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL(for: entry.id, revision: entry.revision), options: .atomic)
    }

    private func verifyFile(_ url: URL, expectedBytes: Int64, expectedSHA256: String) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, Int64(size) == expectedBytes else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest.lowercased() == expectedSHA256.lowercased() else {
            throw OrangeError.writeFailed(url.lastPathComponent)
        }
    }
}
