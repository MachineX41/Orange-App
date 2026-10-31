import Foundation

public enum OutputLocation {
    public static func directory(beside source: URL) -> URL {
        let parent = source.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: parent.path) {
            return parent
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
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
        return stripped.replacingOccurrences(of: "/", with: "-")
    }
}
