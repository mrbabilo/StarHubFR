import Foundation

/// Décide quels mods que smapi.io n'a pas su juger méritent une seconde
/// interrogation, directement auprès de Nexus — et ce que la réponse permet
/// d'affirmer.
///
/// La détection de mises à jour est déléguée à smapi.io. Quand celle-ci répond
/// une erreur, le mod reste sans verdict de **toute** source, et la fenêtre le
/// tait : c'est le défaut levé le 2026-08-27 sur Powered Automation (installé
/// en 1.0.0, publié en 1.025, « has no valid versions » côté smapi.io).
///
/// Mesuré sur le parc réel le 2026-08-27, sur 1 010 `UniqueID` : **122 mods
/// bloqués**, dont
/// - **53 sans verdict Nexus** — le lot que ce fichier retient, ramené à
///   **41 pages** distinctes puis **39** après la règle d'ambiguïté ;
/// - **18 dont l'erreur ne concerne pas Nexus** : leur clé `Nexus:…` a bien
///   été consultée, seule celle de CurseForge, GitHub ou ModDrop a échoué.
///   Les reprendre coûterait 18 requêtes pour rien, et rejouerait un verdict
///   que smapi.io a déjà rendu ;
/// - **51 sans aucun identifiant Nexus** (`Nexus:???`, `Nexus:`, clé absente
///   des deux côtés) : rien à interroger.
///
/// La roadmap prévoyait de reprendre « les mods en erreur qui déclarent une
/// `UpdateKeys: Nexus:…` ». Cette règle-là ramasse justement les 18 qu'il faut
/// écarter, et laisse de côté les 20 mods dont l'identifiant ne vient pas du
/// manifeste mais de `metadata.nexusID` — que smapi.io rend même pour les mods
/// qu'elle ne sait pas juger.
enum NexusFallbackCheck {

    /// Un mod que smapi.io a refusé de juger, tel qu'on le connaît au retour
    /// de la réponse groupée.
    struct Blocked: Equatable {
        let uniqueId: String
        /// Le nom déjà résolu pour l'affichage — le même partout ailleurs.
        let name: String
        /// La version **affirmée** à smapi.io : d'ancre s'il y en a une, de
        /// manifeste sinon. C'est elle qu'on comparera, pas une autre.
        let installedVersion: String
        /// Les `UpdateKeys` telles qu'envoyées, clé synthétique comprise.
        let declaredKeys: [String]
        /// L'identifiant que smapi.io connaît, même sans savoir juger le mod.
        let metadataNexusId: Int?
        /// Les messages d'erreur bruts de smapi.io.
        let errors: [String]

        init(uniqueId: String, name: String, installedVersion: String,
             declaredKeys: [String], metadataNexusId: Int?, errors: [String]) {
            self.uniqueId = uniqueId
            self.name = name
            self.installedVersion = installedVersion
            self.declaredKeys = declaredKeys
            self.metadataNexusId = metadataNexusId
            self.errors = errors
        }
    }

    /// Une page Nexus à interroger, et les mods dont elle tranchera le sort.
    ///
    /// Plusieurs mods par page : sur le parc réel, les sept composants des
    /// *Forgotten Caverns* déclarent tous `Nexus:47216`. Une seule requête
    /// suffit à les juger tous — 53 mods pour 41 pages.
    struct Target: Equatable {
        let nexusId: String
        let mods: [Blocked]
    }

    // MARK: - Plan

    /// Les pages à interroger, par ordre d'identifiant croissant.
    ///
    /// - Parameter blocked: les mods en erreur **et sans suggestion** — un mod
    ///   dont smapi.io a quand même trouvé une mise à jour a son verdict, quoi
    ///   qu'ait dit l'une de ses clés.
    static func plan(_ blocked: [Blocked]) -> [Target] {
        var byPage: [String: [Blocked]] = [:]
        for mod in blocked {
            guard needsNexusVerdict(mod), let id = resolvedNexusId(mod) else { continue }
            byPage[id, default: []].append(mod)
        }
        return byPage
            .filter { !isAmbiguous($0.value) }
            .map { Target(nexusId: $0.key,
                          mods: $0.value.sorted { $0.uniqueId < $1.uniqueId }) }
            // Ordre stable : l'identifiant est numérique, mais comparé comme
            // texte il suffit à rendre les journaux et les tests reproductibles.
            .sorted { $0.nexusId < $1.nexusId }
    }

    /// `true` quand smapi.io n'a **pas** rendu de verdict Nexus pour ce mod.
    ///
    /// Deux cas, et seulement deux :
    /// - le mod ne déclare aucune clé Nexus exploitable, donc smapi.io n'a
    ///   jamais regardé Nexus — mais `metadata.nexusID` nous en donne une ;
    /// - il en déclare une et c'est **elle** qui a échoué.
    ///
    /// Le cas exclu est celui des 18 mods dont seule la clé CurseForge,
    /// GitHub ou ModDrop a échoué : « The CurseForge mod with ID '868705' has
    /// no valid versions » ne dit rien de la page Nexus, que smapi.io a bien
    /// consultée. Les rejouer produirait au mieux le même verdict, au pire une
    /// ligne que smapi.io a déjà écartée.
    private static func needsNexusVerdict(_ mod: Blocked) -> Bool {
        guard declaresUsableNexusKey(mod) else { return true }
        return mod.errors.contains { $0.range(of: "nexus", options: .caseInsensitive) != nil }
    }

    /// L'identifiant à interroger : le manifeste, sauf quand smapi.io le
    /// contredit.
    ///
    /// Le manifeste fait foi tant qu'il n'est pas réfuté — c'est ce que SMAPI
    /// lui-même lit, et la même règle vaut pour l'apprentissage des
    /// identifiants (`NexusIdLearning`). Mais ici la clé déclarée **vient
    /// d'échouer** : on n'entre dans cette fonction que pour des mods dont
    /// smapi.io n'a tiré aucun verdict Nexus. Quand elle échoue *et* que
    /// smapi.io connaît le mod sous un autre identifiant, la déclaration est
    /// démentie par l'expérience, l'autre ne l'est pas. L'asymétrie est un
    /// fait, pas une préférence de source — et c'est ce qui distingue ce cas
    /// de `NexusIdLearning`, qui écrit une préférence durable sans preuve
    /// d'échec.
    ///
    /// Cas réel, celui qui a fait taire la preuve fondatrice : *Automate*
    /// déclare `Nexus:50165` — la page de *Powered Automation*, une clé
    /// copiée par erreur — et smapi.io le connaît sous **1063**, en rendant sa
    /// version. Sans cette règle, les deux mods revendiquaient 50165 avec des
    /// versions différentes et la règle d'ambiguïté les écartait tous les
    /// deux, *Powered Automation* compris. Six mods du parc sont dans ce cas,
    /// dont deux bloqués.
    private static func resolvedNexusId(_ mod: Blocked) -> String? {
        let known = (mod.metadataNexusId ?? 0) > 0 ? String(mod.metadataNexusId!) : nil
        guard let declared = declaredNexusId(mod) else { return known }
        guard let known, known != declared else { return declared }
        return known
    }

    private static func declaresUsableNexusKey(_ mod: Blocked) -> Bool {
        declaredNexusId(mod) != nil
    }

    /// Le premier `Nexus:<entier>` des `UpdateKeys`, s'il y en a un.
    ///
    /// Un identifiant non entier (`Nexus:???`, `Nexus:`, `Nexus:null`) n'en
    /// est pas un : c'est justement le motif `malformedNexusId`, 35 cas sur le
    /// parc. Le suffixe `@variante` que tolère SMAPI est retiré — la page
    /// reste la même.
    private static func declaredNexusId(_ mod: Blocked) -> String? {
        for key in mod.declaredKeys {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("nexus:") else { continue }
            var value = String(trimmed.dropFirst("nexus:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let at = value.firstIndex(of: "@") {
                value = String(value[..<at]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
                  Int(value) ?? 0 > 0 else { continue }
            return String(Int(value)!)
        }
        return nil
    }

    /// Une page revendiquée par des mods qui **ne s'accordent pas** sur leur
    /// version installée ne peut pas les décrire tous.
    ///
    /// Cas réel : `Nexus:38134` est déclaré par *Pretty Anime Portraits*
    /// (10.0.0) et *Pretty Anime Genderbends* (7.0.0) — une seule version de
    /// page, deux verdicts inconciliables. smapi.io ne connaît **ni l'un ni
    /// l'autre** (`metadata.id` vide des deux côtés) : rien ne permet de dire
    /// lequel revendique la page à raison, et ce dernier filet est le seul.
    ///
    /// La collision `Nexus:50165` (*Powered Automation* 1.0.0 contre
    /// *Automate* 2.6.1) se résout **en amont**, dans `resolvedNexusId` : là,
    /// smapi.io tranche. Ce filet-ci ne la voit plus — et c'est bien ainsi,
    /// car il écartait *Powered Automation* avec l'intrus.
    ///
    /// À versions **égales**, il n'y a pas d'ambiguïté : les sept composants
    /// des *Forgotten Caverns* et les quatre modules de *Starblue UI* sont
    /// bien la même publication, et la page les juge tous pareil.
    private static func isAmbiguous(_ mods: [Blocked]) -> Bool {
        guard let first = mods.first else { return true }
        return mods.contains {
            NexusUpdateChecker.compare($0.installedVersion, first.installedVersion) != .orderedSame
        }
    }

    // MARK: - Verdict

    /// Les lignes de mise à jour que cette page justifie.
    ///
    /// - Parameters:
    ///   - pageVersion: la version que l'API Nexus annonce pour la page.
    ///   - uploadedTime: la date de mise en ligne, quand Nexus la donne. À la
    ///     différence de la voie smapi.io, qui la laisse toujours à `nil`,
    ///     cette voie la renseigne.
    static func rows(for target: Target,
                     pageVersion: String,
                     uploadedTime: Date?) -> [NexusUpdateChecker.ModUpdate] {
        let version = pageVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return [] }
        return target.mods.compactMap { mod in
            guard isUpgrade(from: mod.installedVersion, to: version) else { return nil }
            return NexusUpdateChecker.ModUpdate(
                uniqueId: mod.uniqueId,
                name: mod.name,
                installedVersion: mod.installedVersion,
                latestVersion: version,
                nexusModId: target.nexusId,
                url: pageURL(target.nexusId),
                uploadedTime: uploadedTime)
        }
    }

    /// L'adresse de la page, celle qu'ouvre déjà le reste de l'app.
    static func pageURL(_ nexusId: String) -> String {
        "https://www.nexusmods.com/stardewvalley/mods/\(nexusId)"
    }

    /// `true` si la page publie strictement plus récent que ce qui est posé.
    ///
    /// Un cas mérite d'être retiré à `isNewer` : la version installée porte
    /// une pré-version `unofficial`. Par la lettre du semver,
    /// « 1.1.3 » l'emporte sur « 1.1.3-unofficial.1-p1xel8ted » — mais chez
    /// SMAPI cette forme désigne un **correctif communautaire postérieur** à
    /// la publication officielle. Proposer la page reviendrait à conseiller
    /// une régression. Un cas sur le parc réel (`ZeroMeters.SAAT.Mod`), et le
    /// même raisonnement vaut pour tous les `-unofficial` du parc, que
    /// `ModCompatibility` documente déjà comme « justement ce qu'il faut
    /// installer ».
    private static func isUpgrade(from installed: String, to page: String) -> Bool {
        guard NexusUpdateChecker.isNewer(page, installed: installed) else { return false }
        guard isUnofficialBuild(installed) else { return true }
        // Le correctif n'est dépassé que si la page franchit son **numéro**,
        // pas si elle se contente d'égaler le tronc commun.
        return NexusUpdateChecker.compare(page, numericCore(installed)) == .orderedDescending
    }

    private static func isUnofficialBuild(_ version: String) -> Bool {
        guard let dash = version.firstIndex(of: "-") else { return false }
        return version[dash...].range(of: "unofficial", options: .caseInsensitive) != nil
    }

    /// « 1.1.3-unofficial.1-p1xel8ted » → « 1.1.3 ».
    private static func numericCore(_ version: String) -> String {
        var work = version
        if let plus = work.firstIndex(of: "+") { work = String(work[..<plus]) }
        if let dash = work.firstIndex(of: "-") { work = String(work[..<dash]) }
        return work
    }
}
