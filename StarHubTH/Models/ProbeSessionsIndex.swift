import Foundation

/// Lecture en deux passes des fichiers qui grossissent sans fin
/// (`timings.jsonl`, `mod-costs.jsonl`) : l'index ne décode **rien** — la
/// session d'une ligne est repérée par le préfixe `"Session":"`, que la sonde
/// (System.Text.Json) écrit sans espace — et le décodage complet ne porte que
/// les lignes des sessions demandées. Index gardé tant que taille + date de
/// modification des deux fichiers ne changent pas. Verrou explicite : le
/// module Core compile en mode Swift 6.
public final class ProbeSessionsIndex: @unchecked Sendable {
    private struct Entry {
        /// `nil` : pas de session reconnaissable (ligne tronquée dans le
        /// préfixe) — toujours décodée, pour que `unreadableLines` la compte.
        let session: String?
        let range: Range<Int>
    }

    private struct IndexedFile {
        var stamp: ProbeFileStamp?
        var data = Data()
        var entries: [Entry] = []
    }

    private let files: ProbeFiles
    private let lock = NSLock()
    private var loaded = false
    private var timings = IndexedFile()
    private var costs = IndexedFile()

    public init(files: ProbeFiles) {
        self.files = files
    }

    /// `wanted == nil` : toutes les sessions (l'écran d'aperçu).
    public func sessions(keeping wanted: Set<String>?) -> ProbeSessions {
        lock.withLock {
            let timingsStamp = ProbeFileStamp.of(files.timingsURL)
            let costsStamp = ProbeFileStamp.of(files.costsURL)
            if !loaded || timingsStamp != timings.stamp { timings = Self.load(files.timingsURL, timingsStamp) }
            if !loaded || costsStamp != costs.stamp { costs = Self.load(files.costsURL, costsStamp) }
            loaded = true
            let minutes = ProbeJSON.lines(ProbeMinute.self, from: Self.select(timings, keeping: wanted))
            let costLines = ProbeJSON.lines(ProbeModCostMinute.self, from: Self.select(costs, keeping: wanted))
            return ProbeSessions.group(minutes: minutes.records, costs: costLines.records,
                                       unreadableLines: minutes.unreadable + costLines.unreadable)
        }
    }

    // MARK: — Privé

    private static func load(_ url: URL, _ stamp: ProbeFileStamp?) -> IndexedFile {
        let data = FileManager.default.contents(atPath: url.path) ?? Data()
        var entries: [Entry] = []
        var lineStart = data.startIndex
        while lineStart < data.endIndex {
            let lineEnd = data[lineStart...].firstIndex(of: UInt8(ascii: "\n")).map(data.index(after:))
                ?? data.endIndex
            entries.append(Entry(session: session(of: data[lineStart..<lineEnd]), range: lineStart..<lineEnd))
            lineStart = lineEnd
        }
        return IndexedFile(stamp: stamp, data: data, entries: entries)
    }

    private static func session(of line: Data) -> String? {
        guard let prefix = line.range(of: Data("\"Session\":\"".utf8)),
              let end = line[prefix.upperBound...].firstIndex(of: UInt8(ascii: "\""))
        else { return nil }
        let raw = line[prefix.upperBound..<end]
        // `timings.jsonl` échappe le `+` du fuseau (`\u002B`), `mod-costs.jsonl`
        // non : l'identifiant indexé doit être celui du décodage complet, sinon
        // `wanted` ne reconnaît aucune ligne. Chemin rapide sans barre oblique.
        guard raw.contains(UInt8(ascii: "\\")) else { return String(decoding: raw, as: UTF8.self) }
        return try? JSONDecoder().decode(String.self, from: Data("\"".utf8) + raw + Data("\"".utf8))
    }

    private static func select(_ file: IndexedFile, keeping wanted: Set<String>?) -> Data {
        guard let wanted else { return file.data }
        var out = Data()
        for entry in file.entries where entry.session.map(wanted.contains) ?? true {
            out.append(file.data[entry.range])
        }
        return out
    }
}
