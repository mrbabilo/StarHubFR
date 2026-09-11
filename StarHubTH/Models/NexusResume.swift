import Foundation

/// Les décisions de la reprise Nexus (B2-T10) — le QUOI de
/// `recheckBlockedViaNexus`/`fetchNexusFallback`/`finishNexusFallback`
/// (le COMMENT — récursion réseau, progression, drapeaux, publication —
/// reste au ViewModel).
///
/// Extraite du ViewModel le 2026-09-11 (§5 de `docs/REFACTORING.md`, domaine
/// Nexus). Ce qui reste ici est ce que l'utilisateur lit : dans la fenêtre
/// (les lignes que la reprise fait entrer dans le cache), et dans le journal
/// (les verdicts **nommés** — les compteurs seuls ne répondent pas à la
/// seule question qui se pose devant eux : *lequel ?*). Le journal de
/// l'application n'étant pas localisé, les lignes portent leur texte et leur
/// niveau, que l'appelant émet telles quelles.
enum NexusResume {

    /// Une ligne de journal prête à émettre.
    struct JournalLine: Equatable {
        let text: String
        let level: LogLevel
    }

    /// Ce qu'une page a fait à l'état de la reprise.
    struct PageOutcome: Equatable {
        /// Les lignes trouvées, y compris celles des pages précédentes.
        let found: [NexusUpdateChecker.ModUpdate]
        /// Les mods dont Nexus a rendu un verdict — mise à jour trouvée
        /// **ou** confirmation qu'il n'y en a pas : dans les deux cas le mod
        /// n'est plus « non vérifiable ».
        let settled: Set<String>
        let failures: Int
        /// L'abandon sur limitation de débit : le `retryAfter` reçu. `nil`
        /// quand la reprise continue.
        let rateLimitedRetryAfter: TimeInterval?
        /// Ce que la page a eu à dire, dans l'ordre.
        let journal: [JournalLine]
    }

    /// - Parameters:
    ///   - pageIndex: le rang de la page **consommée** — la ligne d'abandon
    ///     le cite (« après N page(s) »).
    static func applyPage(_ result: NexusUpdateChecker.SingleFetchResult,
                          target: NexusFallbackCheck.Target,
                          pageIndex: Int,
                          found: [NexusUpdateChecker.ModUpdate],
                          settled: Set<String>,
                          failures: Int) -> PageOutcome {
        var found = found
        var settled = settled
        var failures = failures
        var journal: [JournalLine] = []
        var rateLimited: TimeInterval? = nil
        switch result {
        case .success(let version, _, let extra, let pageFile):
            // Une page **sans version** n'est pas un verdict. L'API Nexus
            // exige seulement que le champ existe, et une chaîne vide s'y
            // décode sans broncher : la tenir pour « à jour » retirerait le
            // mod des invérifiables sur un quitus inventé — le défaut même
            // que cette reprise existe pour supprimer.
            let page = version.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !page.isEmpty else {
                failures += 1
                journal.append(JournalLine(
                    text: "Reprise Nexus : la page \(target.nexusId) ne publie aucune "
                        + "version — \(target.mods.count) mod(s) toujours sans verdict",
                    level: .warning))
                break
            }
            let rows = NexusFallbackCheck.rows(for: target,
                                               pageVersion: page,
                                               uploadedTime: extra.uploadedTime,
                                               pageFile: pageFile)
            journal.append(contentsOf: pageVerdictJournal(target: target,
                                                          pageVersion: page,
                                                          updates: rows))
            found += rows
            settled.formUnion(target.mods.map(\.uniqueId))
        case .rateLimited(let retryAfter):
            // Inutile d'insister : les suivantes seraient refusées
            // localement, et ce qui a abouti reste acquis.
            journal.append(JournalLine(
                text: "Reprise Nexus interrompue par la limitation de débit "
                    + "(\(Int(retryAfter)) s) après \(pageIndex) page(s)",
                level: .warning))
            rateLimited = retryAfter
        case .noApiKey, .error:
            // Ni arrêt ni journal : une rafale d'erreurs ne doit pas noyer
            // les verdicts déjà gagnés. Mais un échec se compte — le bilan
            // final dira combien.
            failures += 1
        }
        return PageOutcome(found: found, settled: settled, failures: failures,
                           rateLimitedRetryAfter: rateLimited, journal: journal)
    }

    /// Nomme, mod par mod, ce que la page vient de trancher.
    ///
    /// Une mise à jour se retrouve dans la fenêtre, mais un mod **confirmé à
    /// jour** n'apparaît nulle part ailleurs — et c'est précisément le
    /// verdict qu'on venait de gagner, sur des mods qui n'en avaient d'aucune
    /// source. Le taire refaisait, en plus petit, le défaut que toute cette
    /// reprise corrige. Une ligne par mod plutôt qu'une liste sur une seule :
    /// le journal en tient 2 000 et sait chercher, si bien qu'un nom se
    /// retrouve à coup sûr — ce qu'une ligne de cinquante noms rendrait
    /// illisible.
    static func pageVerdictJournal(target: NexusFallbackCheck.Target,
                                   pageVersion: String,
                                   updates: [NexusUpdateChecker.ModUpdate]) -> [JournalLine] {
        let outdated = Set(updates.map(\.uniqueId))
        return target.mods.map { mod in
            // Un manifeste sans champ `Version` existe : ne pas afficher un
            // blanc là où le lecteur attend un numéro.
            let installed = mod.installedVersion.isEmpty ? "version inconnue" : mod.installedVersion
            if outdated.contains(mod.uniqueId) {
                // Préfixe `[MAJ]` pour repérer les mises à jour d'un coup
                // d'œil dans le journal, et niveau `.warning` pour qu'elles
                // soient visuellement distinctes des lignes d'info ordinaires
                // (le rendu SwiftUI applique un glyphe et une couleur dédiés).
                return JournalLine(
                    text: "[MAJ] Reprise Nexus : \(mod.name) — \(installed) → \(pageVersion) "
                        + "(page \(target.nexusId))",
                    level: .warning)
            }
            return JournalLine(
                text: "Reprise Nexus : \(mod.name) à jour (installé \(installed), "
                    + "page \(pageVersion))",
                level: .info)
        }
    }

    /// Le bilan final : les lignes trouvées fusionnées au cache, et le
    /// décompte honnête de la reprise.
    struct Settlement: Equatable {
        /// Le cache tel qu'il doit être réécrit — vide quand rien n'a été
        /// trouvé (l'appelant n'écrit alors pas).
        let merged: [NexusUpdateChecker.ModUpdate]
        /// Le décompte : tenté, trouvé, confirmé à jour, échoué. Une reprise
        /// silencieuse laisserait croire qu'elle n'a rien trouvé alors
        /// qu'elle n'a pas abouti. Le niveau monte en `.warning` dès qu'elle
        /// a trouvé quelque chose.
        let journal: [JournalLine]
    }

    /// - Parameters:
    ///   - cachedRows: les lignes du **cache** — plat, jamais la liste
    ///     consolidée affichée.
    static func settle(found: [NexusUpdateChecker.ModUpdate],
                       settled: Set<String>,
                       failures: Int,
                       attempted: Int,
                       cachedRows: [NexusUpdateChecker.ModUpdate]) -> Settlement {
        var merged: [NexusUpdateChecker.ModUpdate] = []
        if !found.isEmpty {
            // Les lignes Nexus se **substituent** aux lignes précédentes des
            // mêmes mods plutôt que de s'y ajouter : le cache est indexé par
            // `UniqueID`, et deux lignes de même identité donneraient des
            // doublons à un `ForEach`.
            let replaced = Set(found.map(\.uniqueId))
            let kept = cachedRows.filter { !replaced.contains($0.uniqueId) }
            merged = (kept + found).sorted {
                // Déviation consignée (2026-09-11) : départage des ex æquo
                // par `UniqueID` — le code déplacé triait sans départage,
                // et `sorted` n'est pas stable. Même règle que `SmapiVerdicts`.
                if $0.name.lowercased() != $1.name.lowercased() {
                    return $0.name.lowercased() < $1.name.lowercased()
                }
                return $0.uniqueId < $1.uniqueId
            }
        }
        let line = JournalLine(
            text: "[MAJ] Reprise Nexus : \(attempted) page(s) interrogée(s), "
                + "\(found.count) mise(s) à jour trouvée(s), "
                + "\(settled.count - found.count) mod(s) confirmé(s) à jour, "
                + "\(failures) échec(s)",
            level: found.isEmpty ? .info : .warning)
        return Settlement(merged: merged, journal: [line])
    }
}
