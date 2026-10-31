import Foundation
import OrangeKit
import SwiftUI

enum WheelMode: String, Sendable {
    case convert
    case tools
    case actions
}

enum AppearanceChoice: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

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

    static func load(_ url: URL) -> FileRef? {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        let size = Int64((try? standardized.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return FileRef(
            path: standardized.path,
            name: standardized.lastPathComponent,
            kind: Catalog.kind(for: standardized),
            byteCount: size
        )
    }
}

struct WheelChoice: Identifiable, Hashable {
    var id: String
    var title: String
    var symbol: String
    var payload: Payload

    enum Payload: Hashable {
        case convert(ConvertTarget)
        case tool(ToolID)
        case action(ActionID)
    }
}

struct WheelSession: Identifiable {
    let id = UUID()
    var mode: WheelMode
    var files: [FileRef]
    var choices: [WheelChoice]

    var signature: String {
        mode.rawValue + "|" + files.map(\.path).joined(separator: "|")
    }
}

enum SheetRoute: Identifiable {
    case compress([FileRef])
    case resize(FileRef)
    case crop(FileRef)
    case rotate(FileRef)
    case split(FileRef)

    var id: String {
        switch self {
        case .compress(let files): "compress-\(files.map(\.path).joined(separator: "|"))"
        case .resize(let file): "resize-\(file.path)"
        case .crop(let file): "crop-\(file.path)"
        case .rotate(let file): "rotate-\(file.path)"
        case .split(let file): "split-\(file.path)"
        }
    }
}

enum JobState: String, Codable, Sendable {
    case running
    case success
    case failure
}

struct JobRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var createdAt: Date
    var state: JobState
    var outputPaths: [String]
}

enum Section: String, CaseIterable, Identifiable {
    case home
    case library
    case tools

    var id: String { rawValue }
}
