import Foundation

/// X138 — PureBinarySave (palmhacker13, Nexus 54266) garde chaque partie dans
/// `<partie>.bin` et la charge dès que ce fichier existe, sans regarder le
/// XML. Ce que l'app écrit dans le XML serait ignoré au chargement suivant,
/// puis écrasé à la sauvegarde suivante. Mécanique relevée sur la 1.0.7
/// décompilée : `docs/audit-ultrasmooth-2.7.2.md`.
public enum PureBinarySave {
    static let uniqueId = "palmhacker13.PureBinarySave"
    static let spaceCoreId = "spacechase0.SpaceCore"
    static let titleKey = "health_pure_binary_save_title"
    static let detailKey = "health_pure_binary_save_detail"

    /// Ce que le mod lit à la place du XML (le `.bak` en cas de `.bin`
    /// illisible). Ses caches (`.assets.bin`, `.cpcache.bin`) n'en font pas
    /// partie : ils ne portent pas la partie.
    static func binaryFiles(of mainSave: URL) -> [URL] {
        let folder = mainSave.deletingLastPathComponent()
        return [".bin", ".bin.bak", ".bin.tmp"]
            .map { folder.appendingPathComponent(mainSave.lastPathComponent + $0) }
            + [folder.appendingPathComponent("SaveGameInfo.bin")]
    }

    /// Une partie complète, racine `SaveGame`. Au coucher, le mod ne laisse
    /// dans le XML qu'un talon (racine `PureBinarySave`, moins de 500 octets) :
    /// mêmes critères que sa propre réparation au lancement.
    public static func isCompleteSave(_ data: Data) -> Bool {
        guard data.count >= 500 else { return false }
        let head = String(decoding: data.prefix(4096), as: UTF8.self)
        var rest = Substring(head)
        while let open = rest.firstIndex(of: "<") {
            rest = rest[rest.index(after: open)...]
            guard let first = rest.first, first != "?", first != "!" else { continue }
            let name = rest.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
            return name == "SaveGame"
        }
        return false
    }

    /// L'app peut-elle écrire dans cette partie ? Toujours sans `.bin`. Avec
    /// un `.bin`, seulement si le XML est complet et pas plus ancien que lui
    /// de plus de 3 s : sinon la partie vraie est dans le `.bin`, et le mod
    /// reconstruirait de toute façon le XML depuis lui au lancement.
    public static func allowsEditing(_ mainSave: URL) -> Bool {
        let bin = binaryFiles(of: mainSave)[0]
        guard FileManager.default.fileExists(atPath: bin.path) else { return true }
        guard let data = FileManager.default.contents(atPath: mainSave.path), isCompleteSave(data)
        else { return false }
        func date(_ url: URL) -> Date? {
            do { return try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date }
            catch { return nil }
        }
        guard let xmlDate = date(mainSave), let binDate = date(bin) else { return false }
        return binDate.timeIntervalSince(xmlDate) <= 3
    }

    /// Écrit le fichier, puis, si c'est une partie complète, met ses `.bin` à
    /// la Corbeille : le mod charge alors le XML et recrée son `.bin` depuis
    /// lui. La Corbeille plutôt qu'une suppression, et une partie déjà gardée
    /// par le backup qui précède toute écriture de l'app.
    static func write(_ data: Data, to url: URL,
                      setAside: (URL) throws -> Void = {
                          _ = try ModZipInstaller.trashItemGrantingWriteAccess(atPath: $0.path)
                      }) throws {
        try data.write(to: url, options: .atomic)
        guard isCompleteSave(data) else { return }
        for file in binaryFiles(of: url) where FileManager.default.fileExists(atPath: file.path) {
            // Le XML est écrit : un `.bin` resté en place n'annule pas l'écriture.
            do { try setAside(file) } catch { continue }
        }
    }

    /// Sans SpaceCore actif, le mod a été vu sur Mac ne jamais réécrire son
    /// `.bin` au coucher : chaque chargement ramène la partie au jour de sa
    /// conversion (relevés de la sonde du 2026-11-01). Corrigé par l'auteur
    /// en 1.0.8 (« profils sans SpaceCore ou macOS », journal relevé le
    /// 2026-11-03) : l'alerte ne vise que les versions antérieures.
    static let fixedIn = "1.0.8"

    public static func issues(_ mods: [ModItem], _ localized: (String) -> String) -> [HealthIssue] {
        func active(_ id: String) -> ModItem? {
            mods.first { $0.isEnabled && $0.uniqueId.caseInsensitiveCompare(id) == .orderedSame }
        }
        guard let mod = active(uniqueId), active(spaceCoreId) == nil,
              NexusUpdateChecker.compare(mod.version, fixedIn) == .orderedAscending else { return [] }
        return [HealthIssue(id: "pure-binary-save-without-spacecore", severity: .critical,
                            source: .pureBinarySave, title: localized(titleKey),
                            detail: localized(detailKey), actions: [.openMod(query: mod.name)])]
    }
}
