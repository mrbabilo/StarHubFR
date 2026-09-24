import Foundation

/// Où va un fichier de langue livré sans son dossier `i18n`, et sous quelle
/// forme dans le mod hôte (2026-09-24).
extension ManifestlessArchive {

    /// Ce qu'une archive dépose : des fichiers de langue — chacun passe par un
    /// `i18n`, à la racine ou dans un composant (Cape Stardew FR :
    /// `[CP]Annetta/i18n/fr.json`, 2026-09-24) — ou autre chose.
    static func kind(of entries: [Entry]) -> Kind {
        entries.allSatisfy { let path = $0.destination.lowercased()
            return path.hasPrefix("i18n/") || path.contains("/i18n/") } ? .translation : .addon
    }

    /// Des fichiers de langue livrés **sans** leur dossier `i18n` vont dedans.
    ///
    /// Relevé le 2026-09-24 : l'archive de « Jakkk's Quinn - Patch FR »
    /// (Nexus 41740) ne porte que `Patch FR/fr.json`. Déposé tel quel, le
    /// fichier atterrissait à la racine du mod, où SMAPI ne le lit jamais.
    /// Ne s'applique que si **tous** les fichiers sont à plat et portent un nom
    /// de langue (`fr.json`, `default.json`, `pt-BR.json`) : un `config.json`
    /// ou un `content.json` voisin laisse l'archive telle quelle.
    static func relocatingBareLocaleFiles(_ entries: [Entry]) -> [Entry] {
        guard !entries.isEmpty,
              entries.allSatisfy({ !$0.destination.contains("/") && isLocaleFileName($0.destination) })
        else { return entries }
        return entries.map { Entry(source: $0.source, destination: "i18n/" + $0.destination) }
    }

    /// Le rangement des traductions d'un mod hôte, lu sur le disque : les
    /// sous-dossiers de `i18n/` et les `.json` posés à sa racine.
    public struct I18nLayout: Equatable, Sendable {
        public let directories: [String]
        public let rootJSONFiles: [String]
        public init(directories: [String], rootJSONFiles: [String]) {
            self.directories = directories; self.rootJSONFiles = rootJSONFiles
        }

        public static func read(modDirectory: URL, fileManager: FileManager = .default) -> I18nLayout {
            let i18n = modDirectory.appendingPathComponent("i18n", isDirectory: true)
            let names = (try? fileManager.contentsOfDirectory(atPath: i18n.path)) ?? []
            var directories: [String] = []
            var files: [String] = []
            for name in names where !name.hasPrefix(".") {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: i18n.appendingPathComponent(name).path,
                                             isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue { directories.append(name) }
                else if name.lowercased().hasSuffix(".json") { files.append(name) }
            }
            return I18nLayout(directories: directories.sorted(), rootJSONFiles: files.sorted())
        }
    }

    /// Un `i18n/fr.json` à plat ne va pas dans un mod qui range ses
    /// traductions **par sous-dossier** (`i18n/default/…`, `i18n/Fr/…`) : il y
    /// irait dans le sous-dossier de sa langue — l'existant s'il y en a un,
    /// casse comprise.
    ///
    /// Ce n'est pas de la présentation : SMAPI lit un seul rangement. Un seul
    /// `.json` à la racine de `i18n/` lui fait ignorer **tous** les
    /// sous-dossiers, pour toutes les langues (voir `I18nLocaleResolver`) — le
    /// fichier déposé à plat aurait éteint le mod entier, anglais compris.
    /// Demandé par l'utilisateur le 2026-09-24.
    public static func adaptingLocaleLayout(_ plan: Plan, to host: I18nLayout) -> Plan {
        guard plan.kind == .translation, host.rootJSONFiles.isEmpty, !host.directories.isEmpty
        else { return plan }
        let entries = plan.entries.map { entry -> Entry in
            let parts = entry.destination.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].lowercased() == "i18n",
                  isLocaleFileName(String(parts[1])) else { return entry }
            let file = String(parts[1])
            let locale = String(file.dropLast(".json".count))
            let folder = host.directories.first { $0.lowercased() == locale.lowercased() } ?? locale
            return Entry(source: entry.source, destination: "i18n/\(folder)/\(file)")
        }
        return Plan(hostFolderName: plan.hostFolderName, kind: plan.kind, entries: entries)
    }

    static func isLocaleFileName(_ name: String) -> Bool {
        name.range(of: #"^(default|[a-z]{2}(-[a-z]{2,4})?)\.json$"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }
}
