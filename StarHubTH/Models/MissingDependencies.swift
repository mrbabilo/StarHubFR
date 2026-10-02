import Foundation

/// A1-T1 — `UniqueID` → page Nexus et nom, pour une dépendance que le disque
/// ne fournit pas : il n'y a pas de manifeste à lire, seulement l'identifiant
/// que le mod qui l'exige déclare.
///
/// Source : le dump Pathoschild en cache (`PathoschildCompatibilityList`),
/// hors ligne. smapi.io n'ajouterait rien — ses métadonnées viennent du même
/// fichier. Couverture mesurée sur le parc (2026-10-02) : 102 des 245
/// dépendances requises déclarées. Pour le reste, la recherche Nexus par nom
/// reste le dernier recours.
///
/// Construit **une fois** par chargement du dump (`DependencyDirectoryStore`),
/// jamais au rendu d'une ligne : le décodage du dump coûte le fichier entier.
public struct DependencyNexusDirectory: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let nexusId: Int?
        public let name: String?
    }

    private let byUniqueId: [String: Entry]

    public static let empty = DependencyNexusDirectory(byUniqueId: [:])

    private init(byUniqueId: [String: Entry]) {
        self.byUniqueId = byUniqueId
    }

    /// `id` peut lister plusieurs identifiants (`"a.b, a.c"`, renommages) :
    /// chacun est indexé. Un `nexus` nul ou négatif ne désigne pas de page.
    public init(entries: [PathoschildCompatibilityList.Entry]) {
        var out: [String: Entry] = [:]
        for entry in entries {
            let nexusId = entry.nexusID.flatMap { $0 > 0 ? $0 : nil }
            for sub in entry.id.split(separator: ",") {
                let key = sub.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else { continue }
                out[key] = Entry(nexusId: nexusId, name: entry.name)
            }
        }
        self.init(byUniqueId: out)
    }

    /// Casse ignorée, comme SMAPI résout un `UniqueID`.
    public func entry(for uniqueId: String) -> Entry? {
        byUniqueId[uniqueId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    /// Le dump en cache, frais ou non ; vide sans cache.
    public static func loadFromCache(now: Date = Date()) -> DependencyNexusDirectory {
        guard let data = PathoschildCompatibilityList.loadFreshCache(now: now)
                ?? PathoschildCompatibilityList.cachedAnyAgeNow(),
              let entries = PathoschildCompatibilityList.decode(data) else { return .empty }
        return DependencyNexusDirectory(entries: entries)
    }
}

/// Une dépendance requise par au moins un mod **actif**, qu'aucun mod
/// installé — actif ou en pause — ne fournit.
public struct MissingDependency: Identifiable, Equatable, Sendable {
    /// Les identifiants déclarés qu'elle couvre : deux `UniqueID` d'une même
    /// page Nexus ne font qu'un téléchargement.
    public let uniqueIds: [String]
    public let name: String
    public let nexusId: Int?
    /// Les noms des mods actifs qui l'exigent, triés.
    public let requiredBy: [String]

    public var id: String { uniqueIds[0].lowercased() }

    /// SMAPI n'est pas un mod : il s'installe par son installateur.
    public var isSmapi: Bool {
        uniqueIds.contains { ["smapi", "pathoschild.smapi"].contains($0.lowercased()) }
    }
}

public enum MissingDependencies {

    /// Les dépendances requises des mods actifs, absentes du parc.
    ///
    /// - Seuls les mods **actifs** comptent : un mod en pause ne réclame
    ///   rien au jeu. Le composant d'un pack en pause est en pause.
    /// - `installedIds` : tous les `UniqueID` installés, pliés en minuscules
    ///   (`DependencyIndex.installedUniqueIds`) — une dépendance en pause
    ///   n'est pas absente, l'activation en chaîne la rattrape (`TogglePlan`).
    /// - Regroupement par page Nexus quand elle est connue, sinon par
    ///   identifiant. Tri : les plus réclamées d'abord, puis par nom.
    public static func plan(mods: [ModItem], installedIds: Set<String>,
                            directory: DependencyNexusDirectory) -> [MissingDependency] {
        var order: [String] = []
        var uniqueIdsByKey: [String: [String]] = [:]
        var requiredByKey: [String: Set<String>] = [:]
        var nexusByKey: [String: Int] = [:]
        var nameByKey: [String: String] = [:]

        for top in mods where top.isEnabled {
            for mod in top.components where mod.isEnabled {
                for dep in mod.dependencies where dep.isRequired {
                    let uid = dep.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !uid.isEmpty, !installedIds.contains(uid.lowercased()) else { continue }
                    let entry = directory.entry(for: uid)
                    let key = entry?.nexusId.map { "nexus:\($0)" } ?? "uid:\(uid.lowercased())"
                    if uniqueIdsByKey[key] == nil {
                        order.append(key)
                        uniqueIdsByKey[key] = []
                        nexusByKey[key] = entry?.nexusId
                        nameByKey[key] = entry?.name ?? uid.smapiModName
                    }
                    if !uniqueIdsByKey[key, default: []].contains(where: { $0.lowercased() == uid.lowercased() }) {
                        uniqueIdsByKey[key, default: []].append(uid)
                    }
                    requiredByKey[key, default: []].insert(mod.name)
                }
            }
        }

        return order.map { key in
            MissingDependency(uniqueIds: uniqueIdsByKey[key] ?? [],
                              name: nameByKey[key] ?? key,
                              nexusId: nexusByKey[key],
                              requiredBy: (requiredByKey[key] ?? []).sorted {
                                  $0.localizedStandardCompare($1) == .orderedAscending })
        }
        .sorted {
            if $0.requiredBy.count != $1.requiredBy.count { return $0.requiredBy.count > $1.requiredBy.count }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Ce que « Installer les dépendances manquantes » fait de chacune.
    public enum Action: Equatable, Sendable {
        /// Téléchargement dans l'app (compte Premium) ; la feuille
        /// d'installation vérifie que l'archive porte bien `uniqueIds`.
        case download(nexusId: Int, uniqueIds: [String])
        /// Page Nexus à ouvrir : compte gratuit ou sans clé, l'utilisateur
        /// y clique « Mod Manager Download » (`nxm://`).
        case openPage(URL)
        /// Page inconnue : recherche Nexus par nom.
        case search(URL)
    }

    /// Les pages ouvertes d'un coup sont plafonnées (pas d'avalanche
    /// d'onglets, la limite de JuniGrid) ; SMAPI n'entre jamais.
    public static let pageLimit = 12

    public static func actions(for deps: [MissingDependency],
                               canDownloadInApp: Bool) -> [Action] {
        var actions: [Action] = []
        var pages = 0
        for dep in deps where !dep.isSmapi {
            if let nexusId = dep.nexusId, canDownloadInApp {
                actions.append(.download(nexusId: nexusId, uniqueIds: dep.uniqueIds))
                continue
            }
            guard pages < pageLimit else { continue }
            pages += 1
            if let nexusId = dep.nexusId {
                actions.append(.openPage(filesPage(nexusId: nexusId)))
            } else if let url = searchPage(for: dep.name) {
                actions.append(.search(url))
            }
        }
        return actions
    }

    /// L'onglet Fichiers : c'est là que se trouve « Mod Manager Download ».
    public static func filesPage(nexusId: Int) -> URL {
        URL(string: "https://www.nexusmods.com/stardewvalley/mods/\(nexusId)?tab=files")!
    }

    public static func modPage(nexusId: Int) -> URL {
        URL(string: "https://www.nexusmods.com/stardewvalley/mods/\(nexusId)")!
    }

    public static func searchPage(for term: String) -> URL? {
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        return URL(string: "https://www.nexusmods.com/stardewvalley/search/?gsearch=\(encoded)")
    }

    public static func authorPage(for author: String) -> URL? {
        let encoded = author.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? author
        return URL(string: "https://www.nexusmods.com/games/stardewvalley/mods?author=\(encoded)")
    }

    /// Les identifiants attendus qu'une archive ne contient pas — casse
    /// ignorée. Vide : l'archive fournit ce qu'on est venu chercher.
    /// Le fichier MAIN le plus récent d'une page à variantes peut ne pas être
    /// le bon : la feuille d'installation le dit au lieu de l'installer en
    /// silence.
    public static func absent(expected: [String], in detected: [String]) -> [String] {
        let found = Set(detected.map { $0.lowercased() })
        return expected.filter { !found.contains($0.lowercased()) }
    }
}
