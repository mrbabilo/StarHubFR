import Foundation

/// Lecture des fichiers de la sonde StarHubFR (`companion/StarHubFR.Probe`,
/// D4-T2). La sonde les écrit avec `System.Text.Json`, clés en PascalCase
/// (`UniqueID`, `HeapMB`, `P50`) : on passe la première lettre en minuscule,
/// le reste tel quel, pour des propriétés Swift à la casse d'usage.
enum ProbeJSON {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            guard let last = path.last else { return Key(stringValue: "") }
            let raw = last.stringValue
            return Key(stringValue: raw.prefix(1).lowercased() + raw.dropFirst())
        }
        return decoder
    }

    /// Une ligne, un enregistrement. Une ligne illisible (coupée par un arrêt
    /// brutal du jeu, champ obligatoire absent) est **comptée**, jamais levée :
    /// les autres lignes du fichier restent lues.
    static func lines<T: Decodable>(_ type: T.Type, from data: Data) -> (records: [T], unreadable: Int) {
        let decoder = decoder()
        var records: [T] = []
        var unreadable = 0
        for chunk in data.split(separator: UInt8(ascii: "\n")) {
            var line = Data(chunk)
            if line.last == UInt8(ascii: "\r") { line.removeLast() }
            if line.allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }) { continue }
            do {
                records.append(try decoder.decode(T.self, from: line))
            } catch {
                unreadable += 1
            }
        }
        return (records, unreadable)
    }
}

/// Les horodatages de la sonde : `2026-09-26T18:47:26.9145830+02:00`. .NET
/// écrit 7 décimales ; `ISO8601DateFormatter` lit la milliseconde, mais au-delà
/// d'une dizaine de décimales il rend la date **sans sa fraction**, sans
/// erreur (mesuré sur macOS 26.7) : les décimales sont ramenées à 3 avant
/// lecture.
public enum ProbeDate {
    private static let cache = DateCache()

    public static func parse(_ text: String) -> Date? {
        cache.parse(text)
    }

    /// A report reads the same timestamps for seven metrics and their charts.
    /// Bound retained strings; serialize both formatters and memoized values
    /// because background reports and file scans can parse concurrently.
    private final class DateCache: @unchecked Sendable {
        private let lock = NSLock()
        private let whole = ISO8601DateFormatter()
        private let fractional = ISO8601DateFormatter()
        private var dates: [String: Date] = [:]

        init() {
            whole.formatOptions = [.withInternetDateTime]
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        func parse(_ text: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            if let date = dates[text] { return date }
            let date = parseUncached(text)
            if let date {
                if dates.count >= 16_384 { dates.removeAll(keepingCapacity: true) }
                dates[text] = date
            }
            return date
        }

        private func parseUncached(_ text: String) -> Date? {
            var normalized = text
            if let dot = text.firstIndex(of: "."),
               let zone = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                let digits = text[text.index(after: dot)..<zone]
                let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
                normalized = String(text[..<dot]) + "." + millis + String(text[zone...])
            }
            let formatter = normalized.contains(".") ? fractional : whole
            return formatter.date(from: normalized)
        }
    }
}
