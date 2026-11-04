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
    static let staleTitleActiveKey = "health_pure_binary_stale_title_active"
    static let staleTitlePausedKey = "health_pure_binary_stale_title_paused"
    static let staleDetailKey = "health_pure_binary_stale_detail"
    static let staleEntryKey = "health_pure_binary_stale_entry"
    static let refusalStubKey = "save_pure_binary_refusal_stub"
    static let refusalNewerKey = "save_pure_binary_refusal_newer"

    /// Ce que le mod lit à la place du XML (le `.bak` en cas de `.bin`
    /// illisible). Ses caches (`.assets.bin`, `.cpcache.bin`) n'en font pas
    /// partie : ils ne portent pas la partie.
    static func binaryFiles(of mainSave: URL) -> [URL] {
        let folder = mainSave.deletingLastPathComponent()
        return [".bin", ".bin.bak", ".bin.tmp"]
            .map { folder.appendingPathComponent(mainSave.lastPathComponent + $0) }
            + ["SaveGameInfo.bin", "SaveGameInfo.bin.bak", "SaveGameInfo.bin.tmp"]
            .map { folder.appendingPathComponent($0) }
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
    public static func allowsEditing(_ mainSave: URL) -> Bool { refusalKey(for: mainSave) == nil }

    /// Pourquoi l'app refuse d'écrire dans cette partie, en clé de libellé.
    public static func refusalKey(for mainSave: URL) -> String? {
        let bin = binaryFiles(of: mainSave)[0]
        guard FileManager.default.fileExists(atPath: bin.path) else { return nil }
        guard let data = FileManager.default.contents(atPath: mainSave.path), isCompleteSave(data)
        else { return refusalStubKey }
        func date(_ url: URL) -> Date? {
            do { return try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date }
            catch { return nil }
        }
        guard let xmlDate = date(mainSave), let binDate = date(bin) else { return refusalNewerKey }
        return binDate.timeIntervalSince(xmlDate) <= 3 ? nil : refusalNewerKey
    }

    /// La Corbeille plutôt qu'une suppression : le geste se défait.
    static func trash(_ url: URL) throws {
        _ = try ModZipInstaller.trashItemGrantingWriteAccess(atPath: url.path)
    }

    /// Écrit le fichier, puis, si c'est une partie complète, met ses `.bin` à
    /// la Corbeille : le mod charge alors le XML et recrée son `.bin` depuis
    /// lui. La Corbeille plutôt qu'une suppression, et une partie déjà gardée
    /// par le backup qui précède toute écriture de l'app.
    static func write(_ data: Data, to url: URL, setAside: (URL) throws -> Void = trash) throws {
        try data.write(to: url, options: .atomic)
        guard isCompleteSave(data) else { return }
        setAsideBinaries(of: url, setAside: setAside)
    }

    static func setAsideBinaries(of mainSave: URL, setAside: (URL) throws -> Void) {
        for file in binaryFiles(of: mainSave) where FileManager.default.fileExists(atPath: file.path) {
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

    public static func issues(_ mods: [ModItem], stale: [StaleSave] = [],
                              _ localized: (String) -> String) -> [HealthIssue] {
        withoutSpaceCore(mods, localized) + staleIssues(mods, stale, localized)
    }

    /// Une partie qui a avancé sans le mod revient au jour de son `.bin` dès
    /// qu'il la charge. Mod en pause, c'est la réactivation qui la perdrait.
    private static func staleIssues(_ mods: [ModItem], _ stale: [StaleSave],
                                    _ localized: (String) -> String) -> [HealthIssue] {
        guard !stale.isEmpty,
              let mod = mods.first(where: { $0.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame })
        else { return [] }
        let entries = stale.map { String(format: localized(staleEntryKey), $0.name, $0.daysBehind) }
        return [HealthIssue(id: "pure-binary-save-stale", severity: mod.isEnabled ? .critical : .warning,
                            source: .pureBinarySave,
                            title: localized(mod.isEnabled ? staleTitleActiveKey : staleTitlePausedKey),
                            detail: String(format: localized(staleDetailKey), entries.joined(separator: ", ")),
                            actions: [.setAsideStaleBinaries(saves: stale.map(\.path))])]
    }

    private static func withoutSpaceCore(_ mods: [ModItem], _ localized: (String) -> String) -> [HealthIssue] {
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
