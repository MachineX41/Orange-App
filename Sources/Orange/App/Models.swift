import Foundation
import OrangeKit
import SwiftUI

enum WheelMode: String, CaseIterable, Sendable {
    case convert
    case tools
    case actions
}

enum ActionID: String, CaseIterable, Codable, Sendable {
    case float, copy, move, copyPath, duplicate, reveal, airDrop, zip, openTerminal
}

enum AppearanceChoice: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct FileRef: Identifiable, Hashable, Codable, Sendable {
    var path: String
    var name: String
    var kind: MediaKind
    var byteCount: Int64

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    static func load(_ url: URL) -> FileRef? {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else { return nil }
        let size = Int64((try? standardized.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return FileRef(
            path: standardized.path,
            name: standardized.lastPathComponent,
            kind: isDirectory.boolValue ? .other : Catalog.kind(for: standardized),
            byteCount: size
        )
    }
}

struct WheelChoice: Identifiable, Hashable {
    enum Payload: Hashable {
        case convert(ConvertTarget)
        case tool(ToolID)
        case action(ActionID)
        case more
    }

    var id: String
    var title: String
    var symbol: String
    var payload: Payload
}

struct WheelSession: Identifiable, Equatable {
    let id = UUID()
    var mode: WheelMode
    var files: [FileRef]
    var choices: [WheelChoice]

    var signature: String {
        mode.rawValue + "|" + files.map(\.path).joined(separator: "|")
    }

    static func == (lhs: WheelSession, rhs: WheelSession) -> Bool { lhs.id == rhs.id }
}

enum JobState: String, Codable, Sendable {
    case running, success, failure
}

struct JobRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var symbol: String
    var createdAt: Date
    var state: JobState
    var outputPaths: [String]
}

enum AppSection: Hashable, Identifiable {
    case home
    case library
    case download
    case shelf
    case tools(MediaKind)

    var id: String {
        switch self {
        case .home: "home"
        case .library: "library"
        case .download: "download"
        case .shelf: "shelf"
        case .tools(let kind): "tools-\(kind.rawValue)"
        }
    }
}
