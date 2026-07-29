import Foundation

/// File-backed persistence for `ModErrorHistory`.
///
/// Lives in Application Support, not Caches: this is accumulated observation
/// the user may consult weeks later, and it can't be rebuilt once the SMAPI log
/// has been overwritten by the next launch. It is kept out of the install
/// registry (UserDefaults) so growing diagnostic data can never endanger the
/// install/profile data the app depends on.
enum ModErrorHistoryStore {
    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("StarHubTH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mod_error_history.json")
    }

    /// Timestamp of the last SMAPI log folded in, so reloading the same log
    /// (tab switch, refresh button) can't double-count it.
    private struct Payload: Codable {
        var history: ModErrorHistory
        var lastLogDate: Date?
    }

    static func load() -> (history: ModErrorHistory, lastLogDate: Date?) {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return (ModErrorHistory(), nil) }
        return (payload.history, payload.lastLogDate)
    }

    static func save(_ history: ModErrorHistory, lastLogDate: Date?) {
        guard let url = fileURL else { return }
        let payload = Payload(history: history, lastLogDate: lastLogDate)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
