import CryptoKit
import Foundation

/// B6-T1 — une partie chargée **une fois** en arbre XML, modifiée en mémoire,
/// puis écrite d'un coup sous garde.
///
/// **Pourquoi `XMLDocument` et `.nodePreserveAll`.** Mesuré le 2026-11-27 sur
/// deux vraies parties (3,9 et 37,5 Mo) : relue puis réécrite sans changement,
/// la partie ne diffère de l'original que par la forme des éléments vides
/// (`<x />` et `<x></x>` deviennent `<x/>`) et par `standalone="yes"` dans
/// la déclaration — même contenu pour le jeu. 1,6 s de lecture et autant
/// d'écriture sur 37,5 Mo, hors fil principal. Jamais `.documentTidyXML` (il
/// efface les éléments `_…`, X157), jamais `.nodePrettyPrint` (36 → 90 Mo).
///
/// **Garde d'écriture** (B5-T1) : l'empreinte SHA-256 des octets lus est
/// relevée à l'ouverture et **relue juste avant le remplacement** — une partie
/// réécrite entre-temps (le jeu, une autre fenêtre) n'est jamais écrasée par
/// une version plus ancienne. Puis : refus si le `.bin` de PureBinarySave porte
/// la seule copie complète (X138), backup, marque d'octets rendue (X21),
/// écriture atomique.
///
/// Non `Sendable` : un document vit dans la tâche qui l'a ouvert.
final class SaveDocument {
    /// Empreinte d'une partie sur disque : SHA-256 de ses octets et taille.
    struct Stamp: Equatable, Sendable {
        let sha256: String
        let size: Int

        init(of data: Data) {
            sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            size = data.count
        }

        /// Empreinte du fichier tel qu'il est maintenant, `nil` s'il est illisible.
        static func current(of url: URL) -> Stamp? {
            do { return Stamp(of: try Data(contentsOf: url)) } catch { return nil }
        }
    }

    enum Failure: Error, Equatable {
        case unreadable
        case malformed
        /// Le `.bin` porte la seule copie complète : clé L10n du refus (X138).
        case binaryOnly(String)
        /// La partie a changé sur disque depuis l'ouverture.
        case changedOnDisk
        case gameRunning
        case backupFailed
        case writeFailed
    }

    let url: URL
    /// Empreinte des octets lus à l'ouverture.
    let stamp: Stamp
    let document: XMLDocument
    private let hadBOM: Bool

    /// Lit et analyse la partie. Le fichier n'est lu qu'une fois : l'empreinte
    /// vient des mêmes octets que l'arbre.
    init(contentsOf url: URL) throws(Failure) {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw .unreadable }
        let parsed: XMLDocument
        do { parsed = try XMLDocument(data: data, options: [.nodePreserveAll]) } catch { throw .malformed }
        guard parsed.rootElement() != nil else { throw .malformed }
        self.url = url
        self.stamp = Stamp(of: data)
        self.document = parsed
        self.hadBOM = data.starts(with: SaveManager.utf8BOM)
    }

    /// `<SaveGame>` (une partie) ou `<Farmer>` (`SaveGameInfo`).
    var root: XMLElement {
        // Garanti par `init` ; l'arbre n'est jamais vidé de sa racine ici.
        document.rootElement() ?? XMLElement(name: "")
    }

    /// Le fermier principal, `<SaveGame>/<player>`.
    var player: XMLElement? { root.elements(forName: "player").first }

    /// Les octets que `write` poserait : arbre sérialisé sans réindentation,
    /// marque d'octets rendue si l'original la portait.
    func serialized() -> Data {
        SaveManager.bytes(document.xmlData(options: [.nodePreserveAll]), preservingBOM: hadBOM)
    }

    /// Écrit l'arbre à la place de la partie.
    /// - Parameters:
    ///   - expected: empreinte d'une lecture antérieure (l'écran d'édition)
    ///     que le fichier doit encore porter, en plus de celle de l'ouverture.
    ///   - isGameRunning: revérifié **au moment d'écrire**, pas seulement à
    ///     l'ouverture de l'écran.
    ///   - backup: copie de la partie, appelée après les contrôles et avant
    ///     l'écriture ; `false` annule l'écriture.
    func write(expected: Stamp? = nil,
               isGameRunning: () -> Bool = { false },
               backup: () -> Bool) throws(Failure) {
        if let key = PureBinarySave.refusalKey(for: url) { throw .binaryOnly(key) }
        guard !isGameRunning() else { throw .gameRunning }
        try requireUnchanged(expected)
        guard backup() else { throw .backupFailed }
        let payload = serialized()
        // Le backup a pris du temps : relu une dernière fois, au plus près du
        // remplacement.
        try requireUnchanged(expected)
        do { try PureBinarySave.write(payload, to: url) } catch { throw .writeFailed }
    }

    private func requireUnchanged(_ expected: Stamp?) throws(Failure) {
        guard let now = Stamp.current(of: url) else { throw .unreadable }
        guard now == stamp, expected.map({ $0 == now }) ?? true else { throw .changedOnDisk }
    }
}
