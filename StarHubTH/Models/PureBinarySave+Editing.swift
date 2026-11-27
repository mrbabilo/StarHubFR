import Foundation

/// B6-T2 — éditer une partie dont la version vraie est dans le `.bin`.
///
/// Deux cas, ceux que refusait X138 : le XML n'est qu'un talon (le mod a
/// remplacé la partie par `<PureBinarySave …/>` au coucher), ou le XML est
/// complet mais plus ancien que le `.bin` de plus de 3 s (copie XML différée,
/// ou partie jouée sans la copie). La partie vraie est alors lue dans le
/// `.bin`, éditée, puis écrite **en XML complet** ; les `.bin` sont mis à la
/// Corbeille et le mod, au lancement suivant, charge le XML et refait son
/// binaire (garde relue dans la 2.0.8 : `docs/audit-ultrasmooth-2.9.6.md`).
/// L'app n'écrit jamais de `.bin`.
extension PureBinarySave {
    /// Le XML complet que porte le `.bin` quand la partie vraie est là, `nil`
    /// sinon — XML à jour, pas de `.bin`, ou `.bin` illisible.
    /// - Parameter bin: le contenu du `.bin`, s'il est déjà lu.
    static func binaryTruth(of mainSave: URL, bin: Data? = nil) -> Data? {
        guard refusalKey(for: mainSave) != nil,
              let file = bin ?? FileManager.default.contents(atPath: binaryFiles(of: mainSave)[0].path),
              let inner = decoded(file), isCompleteSave(inner) else { return nil }
        return inner
    }

    /// Avant d'écarter les `.bin` d'une partie lue dans le sien : l'écran de
    /// chargement du jeu lit `SaveGameInfo`, qui peut être un talon lui aussi.
    /// Recopié depuis `SaveGameInfo.bin` quand celui-ci porte la version vraie
    /// (XML absent, talon, ou plus ancien de plus de 3 s) ; rien sinon.
    /// - Throws: `SaveGameInfo` serait perdu (`.bin` illisible face à un
    ///   talon) ou n'a pas pu être écrit — la partie ne doit pas être écrite.
    static func restoreLoadScreen(in folder: URL) throws {
        let xmlURL = folder.appendingPathComponent("SaveGameInfo")
        let binURL = folder.appendingPathComponent("SaveGameInfo.bin")
        let manager = FileManager.default
        guard let file = manager.contents(atPath: binURL.path) else { return }
        let xmlIsCurrent = manager.contents(atPath: xmlURL.path).map { isComplete($0, root: "Farmer") } ?? false
        if xmlIsCurrent, let xmlDate = modificationDate(xmlURL), let binDate = modificationDate(binURL),
           binDate.timeIntervalSince(xmlDate) <= 3 { return }
        guard let inner = decoded(file), isComplete(inner, root: "Farmer") else {
            if xmlIsCurrent { return }  // `.bin` illisible : le XML complet reste le meilleur
            throw CocoaError(.fileReadCorruptFile)
        }
        try inner.write(to: xmlURL, options: .atomic)
    }

    static func modificationDate(_ url: URL) -> Date? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date } catch { return nil }
    }
}
