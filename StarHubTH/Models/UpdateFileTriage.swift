import Foundation

/// A1-T11 — ce qu'une mise à jour fait de chaque fichier du dossier installé,
/// selon sa **provenance** et non sa seule présence dans l'archive neuve.
///
/// Le défaut corrigé, mesuré le 2026-09-27 : la règle d'A1-T7 (« absent de
/// l'archive neuve ⇒ donnée locale ») remettait les fichiers que l'auteur
/// avait retirés — 23 assets de Wildroot Chronicles identiques à sa 1.3.5,
/// reportés de version en version ; le code source et une seconde DLL de FOTP
/// (47 fichiers). La liste blanche remettait aussi `i18n/zh.json` **de
/// l'auteur**, d'une vieille version, par-dessus la neuve.
///
/// Règle d'or : sans certitude, on garde (règle 8) ou on pose la version
/// neuve (règle 7), jamais un retrait. Spec :
/// `docs/superpowers/specs/2026-09-27-a1-t11-update-triage-design.md`.
public enum UpdateFileTriage {
    public enum Decision: Equatable, Sendable {
        /// Règle 1 — `config.json`, gardé d'office (comportement d'avant).
        case keepConfig
        /// Règle 2 — déposé par l'app chez cet hôte (traduction, sac).
        case keepDeposit
        /// Règle 3 — identique à une version de l'auteur, absent de l'archive
        /// neuve : l'auteur l'a retiré. Reste dans la sauvegarde.
        case removeGhost
        /// Identique à la version neuve, ou à une version de l'auteur que
        /// l'archive neuve remplace (règle 4, `zh.json` figé).
        case takeNew
        /// Règle 5 — `manifest.json` ou code retouché : la version neuve.
        case replaceStructural
        /// Règle 6 — différent de la référence et de toute version d'auteur.
        case keepRetouch(authorChanged: Bool)
        /// Règle 6b — idem pour un `content.json` : gardé, avec avertissement.
        case keepContentRetouch(authorChanged: Bool)
        /// Règle 7 — sans référence, on ne sait pas : la version neuve.
        case replaceUnverified
        /// Règle 7b — une traduction sans référence : gardée, comme avant.
        case keepUnverifiedTranslation
        /// Règle 8 — jamais livré par l'auteur : local, gardé.
        case keepLocal(authorNowShips: Bool)

        /// Ce que l'installateur remet en place après la copie neuve.
        public var keeps: Bool {
            switch self {
            case .keepConfig, .keepDeposit, .keepRetouch, .keepContentRetouch,
                 .keepUnverifiedTranslation, .keepLocal:
                return true
            case .removeGhost, .takeNew, .replaceStructural, .replaceUnverified:
                return false
            }
        }
    }

    public struct Plan: Equatable, Sendable {
        /// Chemin relatif **du disque** → décision.
        public let decisions: [String: Decision]
        /// Chemins **de l'archive neuve** à ne pas reposer : l'utilisateur les
        /// avait supprimés (journal local seul).
        public let respectedDeletions: [String]
        public let report: UpdateTriageReport
        /// L'archive neuve, pour le journal.
        public let newArchive: ModFolderHasher.Listing
        /// Le fichier Nexus dont l'archive installée est la copie exacte.
        public let sourceFileId: Int?

        public init(decisions: [String: Decision], respectedDeletions: [String],
                    report: UpdateTriageReport, newArchive: ModFolderHasher.Listing,
                    sourceFileId: Int? = nil) {
            self.decisions = decisions
            self.respectedDeletions = respectedDeletions
            self.report = report
            self.newArchive = newArchive
            self.sourceFileId = sourceFileId
        }

        /// Remis avec l'exigence de la liste blanche (un échec arrête
        /// l'installation) : réglages, traductions, dépôts, retouches.
        public var critical: [String] {
            decisions.filter { entry in
                switch entry.value {
                case .keepConfig, .keepDeposit, .keepUnverifiedTranslation,
                     .keepRetouch, .keepContentRetouch: return true
                default: return false
                }
            }.keys.sorted()
        }

        /// Les fichiers locaux (règle 8), gouvernés par le réglage A1-T7.
        public var local: [String] {
            decisions.filter { entry in
                if case .keepLocal = entry.value { return true }
                return false
            }.keys.sorted()
        }
    }

    /// - Parameters:
    ///   - installed: le dossier installé (`ModFolderHasher.listing`).
    ///   - newArchive: l'archive neuve extraite, à la racine du mod.
    ///   - index: les versions de l'auteur (journal local + Nexus récent).
    ///   - installedVersion: la `Version` du `manifest.json` installé.
    ///   - deposits: clés des fichiers déposés par l'app chez cet hôte.
    ///   - nexusIncomplete: la lecture Nexus n'a pas abouti (réseau, délai).
    public static func plan(installed: ModFolderHasher.Listing,
                            newArchive: ModFolderHasher.Listing,
                            index: AuthorFileIndex,
                            installedVersion: String,
                            deposits: Set<String>,
                            nexusIncomplete: Bool = false,
                            sourceFileId: Int? = nil) -> Plan {
        let new = newArchive.byKey
        let reference = index.reference(installedVersion: installedVersion)
        var decisions: [String: Decision] = [:]
        var report = UpdateTriageReport()
        report.nexusIncomplete = nexusIncomplete

        for (path, sha) in installed.hashes {
            let key = ModFilePath.key(path)
            let decision = decide(key: key, sha: sha, new: new, index: index,
                                  reference: reference?.files, deposits: deposits)
            decisions[path] = decision
            report.note(decision, path: path)
        }
        // Illisible : présent dans l'archive neuve → la version neuve (règle
        // 7), jamais figé ; absent → gardé.
        for path in installed.unreadable {
            let decision: Decision = new[ModFilePath.key(path)] != nil
                ? .replaceUnverified : .keepLocal(authorNowShips: false)
            decisions[path] = decision
            report.note(decision, path: path)
        }

        // Suppressions : seulement quand le journal local dit ce qui avait
        // été posé. Déduites de Nexus, une archive à variantes ferait passer
        // pour supprimé ce qui n'a pas été choisi — un fichier requis
        // manquerait.
        var deletions: [String] = []
        if let reference, reference.isLocal {
            let present = Set(installed.hashes.keys.map(ModFilePath.key))
                .union(installed.unreadable.map(ModFilePath.key))
            for path in newArchive.hashes.keys {
                let key = ModFilePath.key(path)
                if !present.contains(key), reference.files[key] != nil { deletions.append(path) }
            }
        }
        report.respectedDeletions = deletions.sorted()
        return Plan(decisions: decisions, respectedDeletions: report.respectedDeletions,
                    report: report.sorted(), newArchive: newArchive, sourceFileId: sourceFileId)
    }

    private static func decide(key: String, sha: String, new: [String: String],
                               index: AuthorFileIndex, reference: [String: Set<String>]?,
                               deposits: Set<String>) -> Decision {
        let name = ModFilePath.lastComponent(key)
        if name == "config.json" { return .keepConfig }
        if deposits.contains(key) { return .keepDeposit }
        if new[key] == sha { return .takeNew }
        if index.isAuthorFile(key, sha: sha) {
            return new[key] != nil ? .takeNew : .removeGhost
        }
        if new[key] != nil, name == "manifest.json" || ModFilePath.isCode(key) {
            return .replaceStructural
        }
        if let shipped = reference?[key] {
            let authorChanged = new[key].map { !shipped.contains($0) } ?? false
            return name == "content.json"
                ? .keepContentRetouch(authorChanged: authorChanged)
                : .keepRetouch(authorChanged: authorChanged)
        }
        if new[key] != nil {
            if ModFilePath.isTranslation(key) { return .keepUnverifiedTranslation }
            if reference == nil || index.shipsPath(key) { return .replaceUnverified }
            return .keepLocal(authorNowShips: true)
        }
        return .keepLocal(authorNowShips: false)
    }
}

/// A1-T11 — ce que l'installateur demande pour chaque mod qu'il remplace :
/// le plan du tri. `nil` : l'installateur garde le comportement d'avant
/// (liste blanche + A1-T7).
public struct UpdateTriageProvider: Sendable {
    public let plan: @Sendable (_ existing: ModItem, _ installedFolder: URL, _ newSource: URL)
        -> UpdateFileTriage.Plan?

    public init(plan: @escaping @Sendable (_ existing: ModItem, _ installedFolder: URL, _ newSource: URL)
                    -> UpdateFileTriage.Plan?) {
        self.plan = plan
    }
}

/// Ce que le bilan et le journal disent d'un tri. Chemins du disque, triés.
public struct UpdateTriageReport: Codable, Equatable, Sendable {
    public var removedGhosts: [String] = []
    public var keptRetouches: [String] = []
    public var retouchesAuthorChanged: [String] = []
    public var contentRetouches: [String] = []
    public var replacedStructural: [String] = []
    public var replacedUnverified: [String] = []
    public var keptUnverifiedTranslations: [String] = []
    public var keptDeposits: [String] = []
    public var keptLocal: [String] = []
    public var authorNowShips: [String] = []
    public var respectedDeletions: [String] = []
    public var nexusIncomplete = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case removedGhosts, keptRetouches, retouchesAuthorChanged, contentRetouches,
             replacedStructural, replacedUnverified, keptUnverifiedTranslations,
             keptDeposits, keptLocal, authorNowShips, respectedDeletions, nexusIncomplete
    }

    /// Tolérant : un champ absent (journal plus ancien) vaut vide, un champ
    /// inconnu (plus récent) est ignoré — sinon tout le journal du mod
    /// passerait pour illisible.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list(_ key: CodingKeys) throws -> [String] { try c.decodeIfPresent([String].self, forKey: key) ?? [] }
        removedGhosts = try list(.removedGhosts)
        keptRetouches = try list(.keptRetouches)
        retouchesAuthorChanged = try list(.retouchesAuthorChanged)
        contentRetouches = try list(.contentRetouches)
        replacedStructural = try list(.replacedStructural)
        replacedUnverified = try list(.replacedUnverified)
        keptUnverifiedTranslations = try list(.keptUnverifiedTranslations)
        keptDeposits = try list(.keptDeposits)
        keptLocal = try list(.keptLocal)
        authorNowShips = try list(.authorNowShips)
        respectedDeletions = try list(.respectedDeletions)
        nexusIncomplete = try c.decodeIfPresent(Bool.self, forKey: .nexusIncomplete) ?? false
    }

    /// Rien à dire : pas de ligne au bilan. Les fichiers locaux gardés en
    /// silence — c'est le cas ordinaire d'une mise à jour — n'en font pas.
    public var isSilent: Bool {
        removedGhosts.isEmpty && keptRetouches.isEmpty && contentRetouches.isEmpty
            && replacedStructural.isEmpty && replacedUnverified.isEmpty
            && keptUnverifiedTranslations.isEmpty && keptDeposits.isEmpty
            && authorNowShips.isEmpty && respectedDeletions.isEmpty && !nexusIncomplete
    }

    mutating func note(_ decision: UpdateFileTriage.Decision, path: String) {
        switch decision {
        case .keepConfig, .takeNew: break
        case .keepDeposit: keptDeposits.append(path)
        case .removeGhost: removedGhosts.append(path)
        case .replaceStructural: replacedStructural.append(path)
        case .keepRetouch(let changed):
            keptRetouches.append(path)
            if changed { retouchesAuthorChanged.append(path) }
        case .keepContentRetouch(let changed):
            contentRetouches.append(path)
            if changed { retouchesAuthorChanged.append(path) }
        case .replaceUnverified: replacedUnverified.append(path)
        case .keepUnverifiedTranslation: keptUnverifiedTranslations.append(path)
        case .keepLocal(let nowShips):
            keptLocal.append(path)
            if nowShips { authorNowShips.append(path) }
        }
    }

    func sorted() -> UpdateTriageReport {
        var copy = self
        copy.removedGhosts.sort()
        copy.keptRetouches.sort()
        copy.retouchesAuthorChanged.sort()
        copy.contentRetouches.sort()
        copy.replacedStructural.sort()
        copy.replacedUnverified.sort()
        copy.keptUnverifiedTranslations.sort()
        copy.keptDeposits.sort()
        copy.keptLocal.sort()
        copy.authorNowShips.sort()
        copy.respectedDeletions.sort()
        return copy
    }
}
