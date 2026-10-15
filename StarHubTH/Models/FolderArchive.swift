import Foundation

/// Ce qu'il faut savoir pour archiver un dossier (`Mods/` ou les parties) en
/// `.zip` : place nécessaire, durée probable, arguments de `zip`, et lecture
/// de son avancement.
///
/// Origine : le bouton « Sauvegarder le dossier des mods » lançait un `zip`
/// muet sur le Bureau. Sur le parc réel (14 Go, 84 147 fichiers sur disque
/// externe, 2026-10-15) il tournait des dizaines de minutes sans rien
/// afficher, et son fichier temporaire `zi…`, visible sur le Bureau, avait
/// fini à la Corbeille — l'archive ne pouvait plus aboutir.
public enum FolderArchive {

    /// Avancement tel que `zip -db -dc` l'écrit avant chaque fichier :
    /// `  4/  3 [1.7M/ 11M]   adding: …` — entrées faites/restantes, octets
    /// faits/restants.
    public struct Progress: Equatable, Sendable {
        public let entriesDone: Int
        public let entriesTotal: Int
        public let bytesDone: Int64
        public let bytesTotal: Int64

        public init(entriesDone: Int, entriesTotal: Int, bytesDone: Int64, bytesTotal: Int64) {
            self.entriesDone = entriesDone
            self.entriesTotal = entriesTotal
            self.bytesDone = bytesDone
            self.bytesTotal = bytesTotal
        }

        /// Part des octets lus, entre 0 et 1.
        public var fraction: Double {
            guard bytesTotal > 0 else { return 0 }
            return min(1, max(0, Double(bytesDone) / Double(bytesTotal)))
        }
    }

    /// Débit retenu tant qu'aucune archive n'a été mesurée : 3,6 Go en
    /// 4 min 30 s environ, relevé sur le parc réel le 2026-10-15 (disque
    /// externe vers disque interne).
    public static let defaultBytesPerSecond: Double = 13_000_000

    /// Formats déjà compressés, stockés tels quels (`zip -n`) : les recompresser
    /// coûte du temps pour un gain nul. Les images et sons font l'essentiel du
    /// poids d'un parc de mods.
    public static let storedSuffixes = [".png", ".jpg", ".jpeg", ".gif", ".ogg", ".mp3", ".wav",
                                        ".xnb", ".zip", ".7z", ".rar", ".gz"]

    // MARK: - Lecture de la sortie de zip

    /// Lit une ligne d'avancement de `zip -db -dc` ; `nil` pour toute autre ligne.
    public static func progress(fromLine line: String) -> Progress? {
        // Seul le préfixe compte : le nom de fichier qui suit peut contenir
        // des crochets ou des barres (`[SMI] Café [v2]/a.json`).
        guard let open = line.firstIndex(of: "["),
              let close = line[open...].firstIndex(of: "]") else { return nil }
        let entries = line[..<open].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        let bytes = line[line.index(after: open)..<close].split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard entries.count == 2, bytes.count == 2,
              let done = Int(entries[0]), let left = Int(entries[1]),
              let bytesDone = Self.bytes(fromZipSize: bytes[0]),
              let bytesLeft = Self.bytes(fromZipSize: bytes[1]) else { return nil }
        return Progress(entriesDone: done, entriesTotal: done + left,
                        bytesDone: bytesDone, bytesTotal: bytesDone + bytesLeft)
    }

    /// `3`, `292K`, `1.7M`, `12G` — unités de 1 024, comme `zip` les écrit.
    public static func bytes(fromZipSize text: String) -> Int64? {
        guard let last = text.last else { return nil }
        let units: [Character: Double] = ["K": 1024, "M": 1_048_576, "G": 1_073_741_824,
                                          "T": 1_099_511_627_776]
        if let unit = units[last] {
            guard let value = Double(text.dropLast()) else { return nil }
            return Int64(value * unit)
        }
        return Int64(text)
    }

    // MARK: - Avant de lancer

    /// Place à exiger sur le disque de destination : la source plus 5 %, et
    /// jamais moins de 200 Mo de marge. Une archive ne dépasse pas sa source
    /// de plus que ses en-têtes ; la marge garde le disque utilisable.
    public static func requiredBytes(sourceBytes: Int64) -> Int64 {
        sourceBytes + max(sourceBytes / 20, 200_000_000)
    }

    /// `true` quand la place suffit — ou quand le système ne la dit pas : une
    /// inconnue ne doit pas interdire la sauvegarde.
    public static func hasEnoughSpace(sourceBytes: Int64, available: Int64?) -> Bool {
        guard let available else { return true }
        return available >= requiredBytes(sourceBytes: sourceBytes)
    }

    /// `true` quand la destination est la source ou un de ses sous-dossiers :
    /// le dossier caché du temporaire naîtrait dans `Mods/` (le scanner y
    /// verrait un mod en pause) et `zip -r .` s'archiverait lui-même.
    /// `Mods2/`, voisin de `Mods/`, n'est pas dedans.
    public static func destination(_ destination: URL, isInside source: URL) -> Bool {
        let inner = destination.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let outer = source.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return inner.count >= outer.count && Array(inner.prefix(outer.count)) == outer
    }

    /// Durée probable, en secondes, au débit donné (le défaut s'il est absurde).
    public static func estimatedSeconds(bytes: Int64, bytesPerSecond: Double) -> Double {
        let rate = bytesPerSecond > 0 ? bytesPerSecond : defaultBytesPerSecond
        return Double(bytes) / rate
    }

    /// Durée restante au débit observé depuis le début ; `nil` tant que rien
    /// n'est lu.
    public static func remainingSeconds(progress: Progress, elapsed: Double) -> Double? {
        guard progress.bytesDone > 0, elapsed > 0 else { return nil }
        let rate = Double(progress.bytesDone) / elapsed
        return Double(progress.bytesTotal - progress.bytesDone) / rate
    }

    /// `StardewMods_2026-10-05_09-07-03.zip` — triable, sans dépendre de la
    /// langue ni contenir de `/` ou de `:`.
    public static func archiveName(prefix: String, date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d-%02d-%02d_%02d-%02d-%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return "\(prefix)_\(stamp).zip"
    }

    /// Arguments de `/usr/bin/zip`, lancé depuis le dossier source :
    /// avancement ligne à ligne (`-db -dc`), temporaire dans un dossier caché
    /// à côté de l'archive (`-b`, même volume : le renommage final reste
    /// atomique), formats compressés stockés (`-n`).
    public static func zipArguments(archive: URL, temporaryFolder: URL) -> [String] {
        ["-r", "-db", "-dc",
         "-n", storedSuffixes.joined(separator: ":"),
         "-b", temporaryFolder.path,
         archive.path, "."]
    }
}
