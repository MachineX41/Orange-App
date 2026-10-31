import Foundation

struct LibrarySnapshot: Codable {
    var jobs: [JobRecord]
    var shelf: [String]
}

@MainActor
final class LibraryStore {
    func load() -> LibrarySnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(LibrarySnapshot.self, from: data) else {
            return LibrarySnapshot(jobs: [], shelf: [])
        }
        return snapshot
    }

    func save(_ snapshot: LibrarySnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private var fileURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Orange", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
