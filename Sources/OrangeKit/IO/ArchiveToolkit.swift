import Foundation

public enum ArchiveToolkit: Sendable {
    public static func zip(urls: [URL], into directory: URL) throws -> URL {
        guard !urls.isEmpty else { throw OrangeError.empty }
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent("orange-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        for url in urls {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                throw OrangeError.unsupported(url.lastPathComponent)
            }
            let copy = staging.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: copy.path) {
                throw OrangeError.unsupported(url.lastPathComponent)
            }
            try fileManager.copyItem(at: url, to: copy)
        }
        let base = urls.count == 1
            ? urls[0].deletingPathExtension().lastPathComponent
            : "Archive"
        let destination = UniqueDestination.url(in: directory, baseName: base, extension: "zip")
        try runDitto(arguments: ["-c", "-k", "--norsrc", staging.path, destination.path])
        return destination
    }

    public static func unzip(archive: URL, into directory: URL) throws -> URL {
        guard archive.pathExtension.lowercased() == "zip" else {
            throw OrangeError.unsupported(archive.lastPathComponent)
        }
        let folder = UniqueDestination.folder(
            in: directory,
            baseName: archive.deletingPathExtension().lastPathComponent
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try runDitto(arguments: ["-x", "-k", "--norsrc", archive.path, folder.path])
            try rejectUnsafeEntries(in: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    private static func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OrangeError.writeFailed("zip")
        }
    }

    private static func rejectUnsafeEntries(in folder: URL) throws {
        let fileManager = FileManager.default
        let root = folder.standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else {
            throw OrangeError.unsafeArchive
        }
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw OrangeError.unsafeArchive
            }
            let path = file.standardizedFileURL.path
            if path != root && !path.hasPrefix(root + "/") {
                throw OrangeError.unsafeArchive
            }
        }
    }
}
