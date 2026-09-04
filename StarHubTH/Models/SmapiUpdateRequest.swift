import Foundation

/// Construit la requête groupée envoyée à `smapi.io/api/v3.0/mods`.
///
/// C'est la source que SMAPI lui-même consulte au démarrage. Elle compare
/// elle-même les versions, en tenant compte des `UpdateKeys` du mod (Nexus,
/// GitHub, CurseForge, ModDrop) — l'app ne calcule plus rien. Mesuré sur le
/// parc réel : 960 mods, 41 mises à jour, 115 diagnostics, sans clé ni quota.
public enum SmapiUpdateRequest {

    /// La version de client déclarée à smapi.io. **Sans elle, l'API ne suggère
    /// aucune mise à jour** : elle répond 200, rend les métadonnées de chaque
    /// mod, et omet simplement `suggestedUpdate`. Un client qui ne s'annonce
    /// pas est traité comme ancien, et l'API le laisse comparer lui-même.
    ///
    /// Mesuré sur le parc réel, à un champ près dans la requête : 42 mises à
    /// jour avec, 0 sans. C'était la panne — la vérification manuelle allait
    /// au bout de ses 7 lots et ne rapportait rien.
    ///
    /// Une **constante**, et non la version de SMAPI installée, sur deux
    /// mesures :
    /// - la valeur ne change pas le résultat : `1.0.0` et `4.1.10` rendent les
    ///   mêmes 42 mises à jour, aux mêmes mods ;
    /// - une valeur vide ne suggère rien, et une valeur malformée fait
    ///   renvoyer une **liste vide** — le lot entier disparaît sans erreur.
    ///
    /// La version installée, elle, est absente quand SMAPI a été posé hors de
    /// l'app (le marqueur est écrit par nous). Faire dépendre la vérification
    /// d'un fichier optionnel pour un gain nul serait rejouer la panne.
    public static let apiVersion = "4.1.10"

    /// Le repli quand la version du jeu n'a pas pu être lue, ou ne s'analyse
    /// pas. Vérifié par test comme bien formé : un repli malformé viderait le
    /// lot qu'il est censé sauver.
    public static let defaultGameVersion = "1.6.15"

    /// La version de jeu à poster — ou le repli.
    ///
    /// Second champ capable de faire disparaître un lot en silence. Mesuré
    /// contre smapi.io : `"1.6.15."` (un point final) et `"x.y.z"` font
    /// renvoyer une **liste vide**, sans erreur HTTP ni message. C'est la
    /// panne d'`apiVersion` par une autre porte.
    ///
    /// Et ce cas est atteignable : la version vient d'une expression
    /// régulière sur l'en-tête du journal SMAPI, `[0-9][0-9.]*`, qui accepte
    /// justement un point final. On ne poste donc que ce que le serveur sait
    /// analyser — une suite de nombres séparés par des points.
    public static func sanitizedGameVersion(_ raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return defaultGameVersion
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        // `isASCII && isNumber`, pas `isNumber` seul : ce dernier accepte les
        // chiffres arabo-indiens et autres, que le serveur n'analyse pas.
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return defaultGameVersion
        }
        return trimmed
    }

    /// La version affirmée est-elle **exprimable** à smapi.io ?
    ///
    /// Troisième champ capable de vider un lot en silence, après `apiVersion`
    /// et `gameVersion` — et le seul qui l'ait fait pour de vrai. Mesuré sur le
    /// parc de l'auteur le 2026-09-03 : **15 ancres** portent une version que
    /// le serveur ne sait pas analyser, et une seule entrée fautive fait rendre
    /// **HTTP 200 avec une liste vide** pour son lot de 150.
    ///
    /// `SmapiUpdateClient` sait re-découper un lot vide pour isoler l'entrée
    /// fautive, mais son budget est de **32 requêtes pour toute la
    /// vérification** : quinze entrées toxiques l'épuisent d'emblée. Rejoué
    /// avec son algorithme : **471 mods rendus sur 1 073**, **4 mises à jour
    /// visibles sur 7**, 40 requêtes au lieu de 8, et deux entrées fautives
    /// nommées sur quinze. Le filet n'est pas un substitut à ne pas envoyer
    /// l'entrée ; il est là pour le manifeste tiers qu'on ne contrôle pas.
    ///
    /// Elles viennent toutes de « Je l'ai déjà », qui enregistre l'étiquette
    /// **Nexus** de la mise à jour — « 5 », « 1.01 », « 1.0.4.1 » — et non une
    /// version SMAPI. C'est voulu côté ancre (voir `affirmInstalled`) : c'est
    /// ici, au moment d'écrire la requête, que la traduction doit se faire.
    ///
    /// ⚠️ **La sévérité du filtre n'est pas négociable.** Un faux négatif coûte
    /// le bénéfice d'une ancre sur un mod ; un faux positif emporte les 150
    /// mods de son lot. Il ne se desserre que contre une mesure, jamais contre
    /// une lecture de la grammaire SemVer.
    ///
    /// Grammaire retenue, calée sur ce que le serveur a accepté et refusé une
    /// requête à la fois : `majeur.mineur[.correctif][-préversion][+build]`,
    /// deux ou trois parties entières, sans zéro de tête, non toutes nulles, et
    /// tenant dans un `Int32` — la longueur est bornée à neuf chiffres plutôt
    /// qu'analysée, un `Int` accepterait `999999999999`.
    public static func isExpressibleVersion(_ raw: String) -> Bool {
        var core = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        // `+build` d'abord, `-préversion` ensuite : `1.0.0+build-x` porte son
        // tiret **dans** le build, le découper à l'envers casserait la lecture.
        if let plus = core.firstIndex(of: "+") {
            let build = core[core.index(after: plus)...]
            guard !build.isEmpty else { return false }
            core = core[..<plus]
        }
        if let dash = core.firstIndex(of: "-") {
            let prerelease = core[core.index(after: dash)...]
            guard !prerelease.isEmpty else { return false }
            core = core[..<dash]
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return false }
        for part in parts {
            guard !part.isEmpty, part.count <= 9,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part == "0" || part.first != "0" else { return false }
        }
        return parts.contains { $0.contains(where: { $0 != "0" }) }
    }

    /// Un dossier de mod tel que le scan l'a vu.
    public struct Candidate {
        public let uniqueId: String
        public let manifestVersion: String
        public let updateKeys: [String]
        /// Un mod en pause est un dossier préfixé par un point : le jeu ne le
        /// charge pas.
        public let isPaused: Bool
        /// Identifiant Nexus saisi par l'utilisateur, quand le manifest n'en
        /// déclare aucun.
        public let manualNexusId: String?

        public init(uniqueId: String, manifestVersion: String, updateKeys: [String],
                    isPaused: Bool, manualNexusId: String?) {
            self.uniqueId = uniqueId
            self.manifestVersion = manifestVersion
            self.updateKeys = updateKeys
            self.isPaused = isPaused
            self.manualNexusId = manualNexusId
        }
    }

    public struct Entry: Encodable, Equatable {
        public let id: String
        public let updateKeys: [String]
        public let installedVersion: String

        public init(id: String, updateKeys: [String], installedVersion: String) {
            self.id = id
            self.updateKeys = updateKeys
            self.installedVersion = installedVersion
        }
    }

    public struct Body: Encodable {
        public let mods: [Entry]
        public let includeExtendedMetadata: Bool
        public let gameVersion: String
        /// **Sensible à la casse, et quatrième champ capable de vider un lot en
        /// silence.** Mesuré contre smapi.io le 2026-09-04 : `"Mac"` répond,
        /// `"macOS"` et `"MacOS"` rendent `HTTP 200` et une **liste vide**.
        /// C'est la panne d'`apiVersion` par une quatrième porte, et la plus
        /// tentante à ouvrir : « macOS » est le nom moderne de la plateforme,
        /// et le corriger « proprement » couperait toute vérification de mise à
        /// jour sans un message. Ne pas y toucher ; `check_sources.py` surveille
        /// ce comportement dans les deux sens.
        public let platform: String
        /// Voir `SmapiUpdateRequest.apiVersion` : sans ce champ, la réponse ne
        /// porte aucune suggestion de mise à jour.
        public let apiVersion: String

        public init(mods: [Entry],
                    includeExtendedMetadata: Bool = true,
                    gameVersion: String,
                    platform: String = "Mac",
                    apiVersion: String = SmapiUpdateRequest.apiVersion) {
            self.mods = mods
            self.includeExtendedMetadata = includeExtendedMetadata
            self.gameVersion = gameVersion
            self.platform = platform
            self.apiVersion = apiVersion
        }
    }

    /// Une entrée **par `UniqueID`**, pas par dossier.
    ///
    /// Sur le parc réel, 6 `UniqueID` sont portés par deux dossiers — Swim Mod
    /// est installé en pack *et* à plat. Envoyer les deux ferait dépendre le
    /// verdict de l'ordre de parcours du disque. Quand deux candidats sont
    /// strictement égaux sur statut et version, on fusionne leurs UpdateKeys
    /// pour garantir le déterminisme : c'est l'union, dédoublonnée, triée.
    ///
    /// - Parameter reportingSubstitution: appelé `(uniqueId, refusée, envoyée)`
    ///   quand la version affirmée n'est pas exprimable et qu'on lui en
    ///   substitue une autre. Un repli muet ici serait exactement le défaut
    ///   qu'il corrige : c'est l'appelant qui le journalise.
    public static func entries(from candidates: [Candidate],
                               anchors: [String: ModVersionAnchor],
                               reportingSubstitution: ((String, String, String) -> Void)? = nil)
        -> [Entry] {
        var best: [String: Candidate] = [:]
        for candidate in candidates where !candidate.uniqueId.isEmpty {
            guard let existing = best[candidate.uniqueId] else {
                best[candidate.uniqueId] = candidate
                continue
            }
            let comparison = compare(candidate, with: existing)
            switch comparison {
            case .prefers:
                best[candidate.uniqueId] = candidate
            case .merges:
                best[candidate.uniqueId] = merge(candidate, with: existing)
            case .keepExisting:
                break
            }
        }
        return best.values
            .sorted { $0.uniqueId < $1.uniqueId }   // ordre stable, pour les tests et les journaux
            .map { candidate in
                Entry(id: candidate.uniqueId,
                      updateKeys: resolvedUpdateKeys(candidate),
                      installedVersion: sentVersion(for: candidate,
                                                    anchored: anchors[candidate.uniqueId]?
                                                        .anchoredVersion,
                                                    reporting: reportingSubstitution))
            }
    }

    /// La version à **comparer** quand le verdict ne vient pas de smapi.io :
    /// l'ancre, toujours — pas ce qu'on a réussi à lui envoyer.
    ///
    /// Les deux valeurs divergent sur un seul cas, et c'est celui qui compte :
    /// une étiquette Nexus libre (« 3 », « 5 », « 1.01 ») n'est pas exprimable
    /// pour smapi.io, à qui l'on envoie donc le manifeste à la place
    /// (`sentVersion` — sans quoi une seule de ces étiquettes vide un lot de
    /// 150 mods). La reprise Nexus, elle, compare à l'**étiquette de la page**,
    /// qui parle exactement ce vocabulaire-là : lui donner ce qu'on a envoyé
    /// revient à comparer « 1.1.5 » à « 3 » et à ressusciter une ligne que
    /// l'utilisateur avait éteinte d'un « Je l'ai déjà ».
    ///
    /// Mesuré sur le parc le 2026-09-04 : **15 des 38 affirmations** revenaient
    /// à chaque vérification, et toutes les 15 portaient une version
    /// inexprimable — quand 22 des 23 silencieuses en portaient une exprimable.
    public static func comparedVersion(anchored: String?, sent: String) -> String {
        let anchor = (anchored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return anchor.isEmpty ? sent : anchor
    }

    public static func batches(_ entries: [Entry], size: Int) -> [[Entry]] {
        guard size > 0 else { return entries.isEmpty ? [] : [entries] }
        return stride(from: 0, to: entries.count, by: size).map {
            Array(entries[$0..<min($0 + size, entries.count)])
        }
    }

    // MARK: - Privé

    /// La version à **poster** : l'ancre si le serveur sait la lire, la version
    /// du manifest sinon, et la chaîne vide en dernier recours.
    ///
    /// Le repli sur le manifest ne ramène aucune ligne éteinte, et c'est
    /// mesuré : aucun des 15 mods concernés du parc n'obtient de suggestion de
    /// smapi.io quand on lui envoie sa version de manifest. L'affirmation, elle,
    /// continue de valoir — `NexusFallbackCheck.Blocked` prend l'ancre **au
    /// retour**, pas ce qu'on a envoyé.
    ///
    /// La chaîne vide est le seul dernier recours sûr : mesurée à la fois
    /// acceptée par le serveur et sans suggestion, elle garde le mod dans la
    /// réponse — et le lot avec lui. Aucun mod du parc n'y tombe aujourd'hui ;
    /// elle couvre le manifest d'un mod à venir dont la version ne s'exprime
    /// pas davantage.
    private static func sentVersion(for candidate: Candidate,
                                    anchored: String?,
                                    reporting: ((String, String, String) -> Void)?) -> String {
        guard let anchored else { return fallback(candidate.manifestVersion) }
        guard !isExpressibleVersion(anchored) else { return anchored }
        let sent = fallback(candidate.manifestVersion)
        reporting?(candidate.uniqueId, anchored, sent)
        return sent
    }

    private static func fallback(_ manifestVersion: String) -> String {
        isExpressibleVersion(manifestVersion) ? manifestVersion : ""
    }

    /// Résultat de la comparaison de deux candidats avec le même UniqueID.
    private enum Comparison {
        case prefers      // le candidat courant remplace l'existant
        case merges       // stricte égalité sur statut et version, fusion requise
        case keepExisting // l'existant reste meilleur
    }

    /// Compare deux candidats pour déterminer lequel retenir.
    /// La priorité est : (1) statut pause, (2) version, (3) fusion si égalité stricte.
    /// La fusion garantit que les UpdateKeys de deux copies identiques ne dépendent
    /// pas de l'ordre de parcours du disque.
    private static func compare(_ candidate: Candidate, with existing: Candidate) -> Comparison {
        // La copie active décrit ce qui tourne ; elle l'emporte sur la copie en pause.
        if existing.isPaused != candidate.isPaused {
            return !candidate.isPaused ? .prefers : .keepExisting
        }

        // Comparaison stricte des versions.
        let candidateIsNewer = NexusUpdateChecker.isNewer(candidate.manifestVersion,
                                                          installed: existing.manifestVersion)
        if candidateIsNewer {
            return .prefers
        }

        let existingIsNewer = NexusUpdateChecker.isNewer(existing.manifestVersion,
                                                         installed: candidate.manifestVersion)
        if existingIsNewer {
            return .keepExisting
        }

        // Versions égales : fusion requise pour le déterminisme.
        return .merges
    }

    /// Fusionne deux candidats strictement égaux (même statut et version).
    /// L'ensemble des UpdateKeys est l'union des deux, dédoublonnée et triée.
    /// Le manualNexusId retenu est le plus petit lexicographiquement, ou nil.
    /// La version retenue est la plus petite chaîne lexicographiquement.
    /// Les deux chaînes comparent égal par construction (`isNewer` est faux
    /// dans les deux sens) ; seule compte la stabilité du choix, pas son
    /// contenu. Sans elle, `"1.0"` et `"1.0.0"` produiraient deux requêtes
    /// différentes selon l'ordre de parcours du disque.
    private static func merge(_ candidate: Candidate, with existing: Candidate) -> Candidate {
        let mergedKeys = Set(candidate.updateKeys + existing.updateKeys)
            .sorted()
        let manualId = [candidate.manualNexusId, existing.manualNexusId]
            .compactMap { $0 }
            .sorted()
            .first
        let version = [candidate.manifestVersion, existing.manifestVersion]
            .sorted()
            .first ?? candidate.manifestVersion

        return Candidate(
            uniqueId: candidate.uniqueId,
            manifestVersion: version,
            updateKeys: mergedKeys,
            isPaused: candidate.isPaused,
            manualNexusId: manualId
        )
    }

    /// L'identifiant saisi à la main devient une `UpdateKey` synthétique —
    /// mais seulement quand le manifest n'en déclare aucune vers Nexus. Le
    /// manifest fait foi : c'est ce que SMAPI lit.
    private static func resolvedUpdateKeys(_ candidate: Candidate) -> [String] {
        let declaresNexus = candidate.updateKeys.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("nexus:")
        }
        guard !declaresNexus,
              let manual = candidate.manualNexusId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !manual.isEmpty else {
            return candidate.updateKeys
        }
        return candidate.updateKeys + ["Nexus:\(manual)"]
    }
}
