import Foundation

public enum OutputLocation {
    nonisolated(unsafe) public static var customDirectory: URL?

    public static func directory(beside source: URL) -> URL {
        if let customDirectory {
            return customDirectory
        }
        let parent = source.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: parent.path) {
            return parent
        }
        return downloads
    }

    public static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    public static func baseName(_ url: URL, suffix: String? = nil) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        guard let suffix, !suffix.isEmpty else { return base }
        return "\(base) \(suffix)"
    }
}

public enum UniqueDestination {
    public static func url(in directory: URL, baseName: String, extension ext: String) -> URL {
        let fileManager = FileManager.default
        let cleaned = sanitize(baseName)
        func candidate(_ suffix: String) -> URL {
            let name = suffix.isEmpty ? cleaned : "\(cleaned) \(suffix)"
            if ext.isEmpty { return directory.appendingPathComponent(name) }
            return directory.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var next = candidate("")
        var index = 2
        while fileManager.fileExists(atPath: next.path) {
            next = candidate(String(index))
            index += 1
        }
        return next
    }

    public static func folder(in directory: URL, baseName: String) -> URL {
        let fileManager = FileManager.default
        let cleaned = sanitize(baseName)
        var candidate = directory.appendingPathComponent(cleaned, isDirectory: true)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(cleaned) \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.isEmpty ? "Orange" : trimmed
        return stripped
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}
