import Foundation

public enum ArchiveToolkit: Sendable {
    public static func zip(urls: [URL], into directory: URL) throws -> URL {
        guard !urls.isEmpty else { throw OrangeError.empty }
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent("orange-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        for url in urls {
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
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", staging.path, destination.path])
        return destination
    }

    public static func extract(archive: URL, into directory: URL) throws -> URL {
        let folder = UniqueDestination.folder(
            in: directory,
            baseName: archive.deletingPathExtension().lastPathComponent
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            if archive.pathExtension.lowercased() == "zip" {
                try run("/usr/bin/ditto", ["-x", "-k", "--norsrc", archive.path, folder.path])
            } else {
                try run("/usr/bin/tar", ["-xf", archive.path, "-C", folder.path])
            }
            try rejectUnsafeEntries(in: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw OrangeError.toolFailed(text.isEmpty ? Lang.t("The archive couldn’t be processed.", "Arşiv işlenemedi.") : text)
        }
    }

    private static func rejectUnsafeEntries(in folder: URL) throws {
        let root = folder.standardizedFileURL.resolvingSymlinksInPath().path
        guard let enumerator = FileManager.default.enumerator(
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
            let path = file.standardizedFileURL.resolvingSymlinksInPath().path
            if path != root && !path.hasPrefix(root + "/") {
                throw OrangeError.unsafeArchive
            }
        }
    }
}
