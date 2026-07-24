import Foundation

struct ModDetailRaw: Codable { let description: String; let changelog: String }

/// File-backed cache (Caches/) for raw mod description + changelog, keyed by
/// modId. Not UserDefaults — these blobs are large.
enum ModDetailCache {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("ModDetails", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func file(_ modId: Int) -> URL { dir.appendingPathComponent("\(modId).json") }

    static func load(modId: Int) -> ModDetailRaw? {
        guard let data = try? Data(contentsOf: file(modId)) else { return nil }
        return try? JSONDecoder().decode(ModDetailRaw.self, from: data)
    }
    static func save(modId: Int, _ raw: ModDetailRaw) {
        if let data = try? JSONEncoder().encode(raw) { try? data.write(to: file(modId), options: .atomic) }
    }
}
