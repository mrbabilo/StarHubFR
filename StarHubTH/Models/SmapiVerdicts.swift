import Foundation

/// L'application d'une réponse smapi.io au parc installé — le QUOI de
/// `applySmapiResults` (le COMMENT — publication, persistance, journal,
/// reprise Nexus — reste au ViewModel).
///
/// Extraite du ViewModel le 2026-09-11 (§5 de `docs/REFACTORING.md`, domaine
/// Nexus) : la classification des verdicts, le filet « sans réponse », la
/// fusion avec le cache plat et la fusion des verdicts de compatibilité
/// décident de ce que l'utilisateur voit, et rien ne les vérifiait. Tout ce
/// que le code déplacé allait chercher sur `self` lui arrive en valeurs
/// (tables d'ancres, index Pathoschild, lignes précédentes du cache, noms
/// installés) ; le journal sort en rapport (`Report`), que l'appelant phrase
/// aux mêmes conditions — patron `SyncReport` du store du registre.
enum SmapiVerdicts {

    /// Un mod que smapi.io n'a pas su juger, prêt pour l'écran.
    struct Unverifiable: Equatable {
        let uniqueId: String
        let name: String
        let blocker: SmapiUpdateResponse.Blocker
    }

    /// Une reprise Nexus déclenchée par le filet « sans réponse » : un fait,
    /// que l'appelant journalise — le Core ne connaît ni le journal de l'app
    /// ni sa localisation.
    struct ResumeTrigger: Equatable {
        let uniqueId: String
        let resolvedId: String
    }

    /// Ce que l'application a constaté, rendu à l'appelant plutôt que
    /// journalisé ici (patron `SyncReport`).
    struct Report: Equatable {
        /// Le filet a poussé ces mods vers la reprise Nexus, avec
        /// l'identifiant qui l'a rendu possible (override manuel ou dump
        /// Pathoschild — la source se lit dans l'`errors` du `Blocked`).
        let resumeTriggered: [ResumeTrigger]
        /// Entrées envoyées sans réponse — « absent de la réponse » n'est pas
        /// « à jour », mais une ligne précédente reste affichable tant qu'elle
        /// est due.
        let unansweredCount: Int
        /// Lignes précédentes retirées : leur mod n'est plus installé.
        let droppedCount: Int
    }

    struct Application: Equatable {
        /// Les suggestions de mise à jour, une ligne par réponse porteur
        /// d'une suggestion. **Une erreur et une suggestion coexistent** :
        /// la suggestion reste un verdict, l'erreur reste un blocage affiché.
        let updates: [NexusUpdateChecker.ModUpdate]
        /// Les mods invérifiables, triés par nom (ex æquo départagés par
        /// `UniqueID`).
        let unverifiable: [Unverifiable]
        /// Les mods à reprendre par Nexus : erreur sans suggestion, ou
        /// absence de réponse résolue par le filet.
        let blocked: [NexusFallbackCheck.Blocked]
        /// Le cache plat tel qu'il doit être réécrit : suggestions du jour +
        /// lignes précédentes encore dues, trié par nom (ex æquo départagés
        /// par `UniqueID`).
        let merged: [NexusUpdateChecker.ModUpdate]
        /// Les verdicts de compatibilité fusionnés puis purgés du parc
        /// envoyé.
        let verdicts: [String: ModCompatibility]
        let report: Report
    }

    /// - Parameters:
    ///   - mods: ce que smapi.io a répondu (une entrée peut manquer à cette
    ///     liste sans être en erreur pour autant — lot partiels mesurés).
    ///   - entries: exactement ce qui a été envoyé — « le parc tel
    ///     qu'interrogé ». Il borne la purge et le filet.
    ///   - installedNames: `UniqueID` → nom que le parc affiche, pour qu'un
    ///     même mod ne change pas de nom d'un écran à l'autre.
    ///   - anchors: `UniqueID` → ancre de version. C'est **l'ancre** qui
    ///     commande la version comparée de la reprise, et l'affirmation qui
    ///     rend (ou non) une ligne précédente encore due.
    ///   - pathoschildIndex: `UniqueID` → identifiant Nexus du dump, repli du
    ///     filet après l'override manuel.
    ///   - previousRows: les lignes du **cache** — plat, jamais la liste
    ///     consolidée affichée.
    ///   - previousVerdicts: les verdicts de compatibilité de la passe
    ///     précédente, fusionnés et non remplacés.
    static func apply(_ mods: [SmapiUpdateResponse.Mod],
                      entries: [SmapiUpdateRequest.Entry],
                      installedNames: [String: String],
                      anchors: [String: ModVersionAnchor],
                      pathoschildIndex: [String: Int],
                      previousRows: [NexusUpdateChecker.ModUpdate],
                      previousVerdicts: [String: ModCompatibility]) -> Application {
        let assertedVersion = Dictionary(entries.map { ($0.id, $0.installedVersion) },
                                         uniquingKeysWith: { first, _ in first })
        // Les `UpdateKeys` telles qu'envoyées — donc y compris la clé
        // synthétique construite depuis un identifiant saisi à la main. C'est
        // le repli quand smapi.io ne connaît pas le mod ; voir
        // `ModManifest.resolveNexusId`.
        let declaredKeys = Dictionary(entries.map { ($0.id, $0.updateKeys) },
                                      uniquingKeysWith: { first, _ in first })
        var updates: [NexusUpdateChecker.ModUpdate] = []
        var unverifiable: [Unverifiable] = []
        // Le matériau de la reprise Nexus (B2-T10). Seuls les mods **sans
        // suggestion** y entrent : une mise à jour trouvée est un verdict,
        // quoi qu'ait dit l'une des autres clés du mod.
        var blocked: [NexusFallbackCheck.Blocked] = []

        for mod in mods {
            if let first = mod.errors.first {
                // Même résolution de nom que les lignes de mise à jour : un
                // mod ne doit pas changer de nom d'un écran à l'autre.
                let name = ModManifest.resolveDisplayName(
                    installedName: installedNames[mod.id],
                    metadataName: mod.metadata?.name,
                    uniqueId: mod.id)
                unverifiable.append(Unverifiable(uniqueId: mod.id, name: name,
                                                 blocker: SmapiUpdateResponse.blocker(for: first)))
                if mod.suggestedUpdate == nil {
                    blocked.append(NexusFallbackCheck.Blocked(
                        uniqueId: mod.id,
                        name: name,
                        // La version **affirmée** — l'ancre, pas ce qu'on a
                        // envoyé. Les deux diffèrent quand l'ancre est une
                        // étiquette Nexus libre que smapi.io ne sait pas lire :
                        // on lui a alors envoyé le manifeste, mais la page
                        // Nexus, elle, parle ce vocabulaire-là. Comparer
                        // l'envoi ferait reparaître une ligne éteinte.
                        installedVersion: SmapiUpdateRequest.comparedVersion(
                            anchored: anchors[mod.id]?.anchoredVersion,
                            sent: assertedVersion[mod.id] ?? ""),
                        declaredKeys: declaredKeys[mod.id] ?? [],
                        metadataNexusId: mod.metadata?.nexusID,
                        errors: mod.errors,
                        // X9 : le fichier que l'app a elle-même posé sur la
                        // page de ce mod, s'il y en a un — la reprise Nexus en
                        // fera son verdict (« plus récent que celui qu'on
                        // tient ») au lieu du libellé.
                        heldFacts: anchors[mod.id]?.nexusFacts))
                }
            }
            guard let suggested = mod.suggestedUpdate else { continue }
            updates.append(NexusUpdateChecker.ModUpdate(
                uniqueId: mod.id,
                name: ModManifest.resolveDisplayName(installedName: installedNames[mod.id],
                                                     metadataName: mod.metadata?.name,
                                                     uniqueId: mod.id),
                installedVersion: assertedVersion[mod.id] ?? "",
                latestVersion: suggested.version,
                // `?? mod.id` reste la sentinelle : un mod suivi seulement par
                // GitHub ou CurseForge n'a pas de page Nexus, et sa ligne doit
                // légitimement rester sans bouton de téléchargement.
                nexusModId: ModManifest.resolveNexusId(
                    metadataNexusID: mod.metadata?.nexusID,
                    updateKeys: declaredKeys[mod.id]) ?? mod.id,
                url: suggested.url ?? "",
                uploadedTime: nil))
        }

        // Un mod ABSENT de la réponse n'a pas de verdict — il n'est pas « à
        // jour ». Le client rend ce qui a abouti même quand un lot échoue :
        // sur 7 lots, un 503 au quatrième laisse ~510 mods sans réponse.
        // Les traiter comme confirmés serait le défaut d'origine sous une
        // autre forme. On conserve donc leur ligne précédente.
        let answered = Set(mods.map(\.id))

        // Mods ENVOYÉS mais SANS réponse smapi.io : smapi.io omet
        // silencieusement les `UniqueID` qu'elle ne connaît pas, et c'est
        // précisément le défaut vu sur UltraSmooth / 50971 : le champ
        // `metadata` revient `nil`, sans erreur, et la reprise Nexus n'est
        // jamais déclenchée parce que la branche au-dessus ne peuple `blocked`
        // que sur `errors.first`.
        //
        // Filet : l'override manuel d'abord — c'est lui que l'utilisateur a
        // posé, et c'est lui qui prime sur tout ; sinon l'index Pathoschild
        // (`UniqueID → nexusID` offline). Sans aucun des deux, le mod reste
        // muet — l'utilisateur a le champ « Nexus Mod ID » dans la fiche
        // détail pour saisir l'identifiant.
        var resumeTriggered: [ResumeTrigger] = []
        for entry in entries where !answered.contains(entry.id) {
            guard !entry.id.isEmpty else { continue }
            let manualId = ModManifest.parseNexusId(fromUpdateKeys: entry.updateKeys)?.id
            let pathoschildId = pathoschildIndex[entry.id].map(String.init)
            let resolvedId = manualId ?? pathoschildId
            guard let id = resolvedId else { continue }
            let name = installedNames[entry.id] ?? entry.id
            blocked.append(NexusFallbackCheck.Blocked(
                uniqueId: entry.id,
                name: name,
                // Même règle que plus haut : l'ancre commande la comparaison,
                // et `assertedVersion` ne sert que de repli — l'entrée a été
                // construite pour smapi.io, qui n'a rien répondu.
                installedVersion: SmapiUpdateRequest.comparedVersion(
                    anchored: anchors[entry.id]?.anchoredVersion,
                    sent: assertedVersion[entry.id] ?? ""),
                declaredKeys: entry.updateKeys,
                metadataNexusId: Int(id),
                // Préfixe `nexus:` volontaire : `NexusFallbackCheck.needsNexusVerdict`
                // matche sur ce fragment pour décider de la reprise.
                errors: ["nexus: no smapi.io answer; resolved via \(manualId != nil ? "manual override" : "Pathoschild dump")"],
                heldFacts: anchors[entry.id]?.nexusFacts))
            resumeTriggered.append(ResumeTrigger(uniqueId: entry.id, resolvedId: id))
        }

        // …mais une ligne n'est conservée que si son mod est **encore
        // installé**. Sans elle, une ligne de mod désinstallé n'est jamais
        // « répondue », donc conservée à vie. `entries` décrit exactement le
        // parc envoyé.
        let stillInstalled = Set(entries.map(\.id))
        let unanswered = previousRows.filter {
            guard !answered.contains($0.id), stillInstalled.contains($0.id) else { return false }
            // …et seulement tant qu'elle est encore due. Une ligne posée avant
            // un « Je l'ai déjà » n'était jamais reconfrontée à l'ancre : elle
            // survivait à toutes les passes suivantes, faute d'être « répondue ».
            return AffirmedUpdates.isStillDue(
                $0, anchored: anchors[$0.id]?.anchoredVersion)
        }
        let dropped = previousRows.filter {
            !answered.contains($0.id) && !stillInstalled.contains($0.id)
        }.count

        let merged = (updates + unanswered).sorted {
            // Déviation consignée (2026-09-11) : le code déplacé triait sans
            // départage — `sorted` n'étant pas stable, deux homonymes
            // changeaient d'ordre d'une vérification à l'autre. C'est la
            // règle déjà appliquée à `unverifiable` (au dessous) et au
            // cadrage de la liste (lot 3) ; un test l'épingle.
            if $0.name.lowercased() != $1.name.lowercased() {
                return $0.name.lowercased() < $1.name.lowercased()
            }
            return $0.uniqueId < $1.uniqueId
        }
        // Même ordre que les mises à jour, et pour la même raison : la
        // réponse smapi.io suit l'ordre d'envoi, pas un ordre lisible. Un
        // seul tri, départagé par l'`UniqueID` : deux mods peuvent porter le
        // même nom, et `sorted` n'est pas stable en Swift — l'ordre de deux
        // homonymes changerait alors d'une vérification à l'autre.
        let sortedUnverifiable = unverifiable.sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            return byName == .orderedSame ? $0.uniqueId < $1.uniqueId : byName == .orderedAscending
        }

        // Les verdicts de compatibilité, que la réponse portait déjà et que
        // personne ne lisait. Fusionnés et non remplacés, pour la raison qui
        // vaut pour les lignes de mise à jour : un lot en échec laisse des
        // mods sans réponse, et les oublier effacerait un « cassé depuis la
        // 1.6 » que rien ne contredit.
        var verdicts = previousVerdicts
        for mod in mods {
            guard let metadata = mod.metadata else { continue }
            if let verdict = ModCompatibility.from(status: metadata.compatibilityStatus,
                                                   brokeIn: metadata.brokeIn,
                                                   summary: metadata.compatibilitySummary) {
                verdicts[mod.id] = verdict
            } else {
                // smapi.io ne sait rien de ce mod : retirer un verdict devenu
                // caduc vaut mieux que d'afficher celui d'avant.
                verdicts.removeValue(forKey: mod.id)
            }
        }
        // Un mod désinstallé n'a plus de verdict à porter.
        verdicts = verdicts.filter { stillInstalled.contains($0.key) }

        return Application(
            updates: updates,
            unverifiable: sortedUnverifiable,
            blocked: blocked,
            merged: merged,
            verdicts: verdicts,
            report: Report(
                resumeTriggered: resumeTriggered,
                unansweredCount: unanswered.count,
                droppedCount: dropped))
    }
}
