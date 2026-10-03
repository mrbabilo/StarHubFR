import Foundation

/// E2-T1 — le rapport de la liste de mods, exportable pour le support et le
/// suivi : les anomalies en tête, puis une ligne par mod (version, état,
/// couverture FR, source Nexus).
///
/// Pur, sur le modèle de `KeybindReportExport` : les lignes arrivent
/// préparées (`Entry`), l'écriture du fichier reste à l'appelant. La collecte
/// des données (anomalies, couverture, identifiant Nexus) vit chez l'appelant
/// — elle dépend de l'état du ViewModel, ce texte non.
///
/// Deux formats, un seul contenu :
/// - **compact** (`compact`), Markdown à coller dans un fil de discussion ;
/// - **complet** (`html`), document autonome à archiver ou joindre.
///
/// Comme le rapport de raccourcis, les sections vides ne s'écrivent pas :
/// un parc sain ne dit pas « anomalies : aucune », il donne l'inventaire.
public enum ModlistReport {

    /// Une ligne du rapport. Le nom est celui affiché ; tout le reste est
    /// déjà résolu (pas de lecture disque ici).
    public struct Entry {
        public let name: String
        public let version: String
        /// `true` quand le dossier est préfixé d'un point : SMAPI ne le charge pas.
        public let isPaused: Bool
        /// Nombre de composants pour un en-tête de pack, `nil` sinon.
        public let packComponentCount: Int?
        /// Couverture FR en pourcentage entier, `nil` sans traduction française.
        public let frPercent: Int?
        /// Identifiant Nexus, `nil` sans page connue.
        public let nexusId: String?
        /// Ce qui cloche, en clair (`reason(for:)`), `nil` si le mod est sain.
        public let anomalyReason: String?
        public let anomalyIsError: Bool

        public init(name: String, version: String, isPaused: Bool,
                    packComponentCount: Int?, frPercent: Int?,
                    nexusId: String?, anomalyReason: String?,
                    anomalyIsError: Bool) {
            self.name = name
            self.version = version
            self.isPaused = isPaused
            self.packComponentCount = packComponentCount
            self.frPercent = frPercent
            self.nexusId = nexusId
            self.anomalyReason = anomalyReason
            self.anomalyIsError = anomalyIsError
        }
    }

    // MARK: - Collecte

    /// Les lignes du rapport depuis les mods de la liste : un en-tête de pack
    /// rend ses composants (`ModItem.components`), l'en-tête porte le compte
    /// et l'anomalie agrégée, chaque composant les siens.
    ///
    /// Chaque source de donnée arrive en paramètre — l'historique SMAPI, la
    /// règle de dépendance, les doublons, les verdicts smapi.io, la couverture
    /// FR connue (`FrenchCoveragePass`, par nom **logique**) et la surcharge
    /// manuelle d'identifiant Nexus. Pur : aucun accès disque, la version
    /// testable de ce que le ViewModel a déjà en mémoire.
    ///
    /// L'identifiant Nexus affiché : la surcharge manuelle d'abord (c'est une
    /// correction de l'app), l'identifiant du manifeste ensuite.
    public static func collect(
        mods: [ModItem],
        history: ModErrorHistory = .init(),
        dependencyIssue: (ModItem) -> Bool = { _ in false },
        duplicates: ModDuplicateIndex = .empty,
        compatibility: [String: ModCompatibility.Status] = [:],
        coverage: [String: TranslationCoverage.Coverage] = [:],
        nexusId: (ModItem) -> String? = { _ in nil }
    ) -> [Entry] {
        func row(for subject: ModItem, packComponentCount: Int?) -> Entry {
            let anomaly = ModAnomalyReport.anomaly(
                for: subject, history: history,
                dependencyIssue: dependencyIssue,
                duplicates: duplicates, compatibility: compatibility)
            let manifestId = subject.nexusModId.isEmpty ? nil : subject.nexusModId
            return Entry(
                name: subject.name,
                version: subject.version,
                isPaused: !subject.isEnabled,
                packComponentCount: packComponentCount,
                frPercent: coverage[subject.folderName]?.displayPercent,
                nexusId: nexusId(subject) ?? manifestId,
                anomalyReason: anomaly.map { reason(for: $0) },
                anomalyIsError: anomaly?.severity == .error)
        }

        return mods.flatMap { mod -> [Entry] in
            // L'en-tête de pack rend sa propre ligne (compte, anomalie
            // agrégée à ses composants), puis chaque composant la sienne.
            var rows = [row(for: mod,
                            packComponentCount: mod.isGroup ? mod.children?.count : nil)]
            if let children = mod.children {
                rows += children.map { row(for: $0, packComponentCount: nil) }
            }
            return rows
        }
    }

    // MARK: - Raison d'anomalie

    /// Ce qui cloche pour un mod, en clair, dans un ordre fixe — le même
    /// résumé quelle que soit la ligne, pour qu'un fil de discussion se lise
    /// sans retourner à l'app.
    public static func reason(for anomaly: ModAnomaly) -> String {
        var parts: [String] = []
        if anomaly.errorCount > 0 {
            parts.append(plural(anomaly.errorCount, "erreur", "erreurs"))
        }
        if anomaly.warningCount > 0 {
            parts.append(plural(anomaly.warningCount, "avertissement", "avertissements"))
        }
        if anomaly.hasDependencyIssue { parts.append("dépendance manquante") }
        if anomaly.isUnloadable { parts.append("manifeste sans identifiant") }
        if let duplicate = anomaly.duplicate {
            parts.append("doublon ×\(duplicate.copies)")
        }
        if let compatibility = anomaly.compatibility {
            parts.append("\(Self.compatLabel(compatibility)) (smapi.io)")
        }
        if anomaly.renamed != nil { parts.append("copie renommée") }
        return parts.joined(separator: " · ")
    }

    private static func compatLabel(_ status: ModCompatibility.Status) -> String {
        switch status {
        case .ok: return "ok"
        case .workaround: return "contournement"
        case .unofficial: return "non officiel"
        case .obsolete: return "obsolète"
        case .abandoned: return "abandonné"
        case .broken: return "cassé"
        }
    }

    private static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    /// Les anomalies d'abord : erreurs avant avertissements, puis l'ordre
    /// naturel de la liste — le même tri aux deux formats.
    private static func sortedAnomalies(in entries: [Entry]) -> [Entry] {
        entries.filter { $0.anomalyReason != nil }.sorted { lhs, rhs in
            if lhs.anomalyIsError != rhs.anomalyIsError { return lhs.anomalyIsError }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Markdown compact

    /// Le rapport en Markdown, à coller dans un post. Une ligne par mod ;
    /// le format table tient dans un message même sur un gros parc.
    public static func compact(entries: [Entry], generatedAt: Date) -> String {
        var out: [String] = []
        out.append("# Rapport de la liste de mods")
        out.append("")
        out.append("_\(headerLine(entries: entries, generatedAt: generatedAt))_")
        out.append("")

        let anomalous = sortedAnomalies(in: entries)
        if !anomalous.isEmpty {
            out.append("## Anomalies")
            out.append("")
            out.append("| Mod | Gravité | Problème |")
            out.append("|---|---|---|")
            for entry in anomalous {
                let severity = entry.anomalyIsError ? "erreur" : "attention"
                out.append("| \(entry.name) | \(severity) | \(entry.anomalyReason ?? "") |")
            }
            out.append("")
        }

        out.append("## Inventaire")
        out.append("")
        out.append("| Mod | Version | État | FR | Source |")
        out.append("|---|---|---|---|---|")
        for entry in entries {
            out.append("| \(entry.name) | \(entry.version) | \(state(entry)) "
                       + "| \(french(entry)) | \(source(entry)) |")
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: - HTML complet

    /// Le même rapport en document HTML autonome : styles en ligne, aucune
    /// ressource externe, pensé pour l'archive et la pièce jointe.
    public static func html(entries: [Entry], generatedAt: Date) -> String {
        var rows: [String] = []
        let anomalous = sortedAnomalies(in: entries)
        if !anomalous.isEmpty {
            rows.append("<h2>Anomalies</h2>")
            rows.append("<table><thead><tr><th>Mod</th><th>Gravité</th>"
                        + "<th>Problème</th></tr></thead><tbody>")
            for entry in anomalous {
                let severity = entry.anomalyIsError ? "erreur" : "attention"
                rows.append("<tr class=\"\(entry.anomalyIsError ? "error" : "warning")\">"
                            + "<td>\(entry.name)</td><td>\(severity)</td>"
                            + "<td>\(entry.anomalyReason ?? "")</td></tr>")
            }
            rows.append("</tbody></table>")
        }

        rows.append("<h2>Inventaire</h2>")
        rows.append("<table><thead><tr><th>Mod</th><th>Version</th><th>État</th>"
                    + "<th>FR</th><th>Source</th></tr></thead><tbody>")
        for entry in entries {
            rows.append("<tr><td>\(entry.name)</td><td>\(entry.version)</td>"
                        + "<td>\(state(entry))</td><td>\(french(entry))</td>"
                        + "<td>\(source(entry))</td></tr>")
        }
        rows.append("</tbody></table>")

        return """
        <!DOCTYPE html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <title>Liste de mods — StarHubFR</title>
        <style>
        body { font-family: -apple-system, sans-serif; margin: 2rem; color: #1d1d1f; }
        h1 { font-size: 1.4rem; } h2 { font-size: 1.1rem; margin-top: 2rem; }
        .meta { color: #6e6e73; font-style: italic; }
        table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
        th, td { text-align: left; padding: 0.3rem 0.6rem; border-bottom: 1px solid #d2d2d7; }
        tr.error td { color: #b3261e; } tr.warning td { color: #9a6b00; }
        </style>
        </head>
        <body>
        <h1>Liste de mods</h1>
        <p class="meta">\(headerLine(entries: entries, generatedAt: generatedAt))</p>
        \(rows.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    // MARK: - Cellules partagées

    private static func headerLine(entries: [Entry], generatedAt: Date) -> String {
        let anomalies = entries.filter { $0.anomalyReason != nil }.count
        let paused = entries.filter { $0.isPaused }.count
        let french = entries.filter { $0.frPercent != nil }.count
        return "\(plural(entries.count, "mod", "mods")) · "
            + "\(plural(anomalies, "anomalie", "anomalies")) · "
            + "\(plural(paused, "en pause", "en pause")) · "
            + "\(plural(french, "en français", "en français")) · "
            + "généré le \(KeybindReportExport.dateFormatter.string(from: generatedAt)) "
            + "par StarHubFR."
    }

    /// « actif », « en pause », « pack · 3 », « pack en pause · 3 ».
    private static func state(_ entry: Entry) -> String {
        var label = entry.isPaused ? "en pause" : "actif"
        if let count = entry.packComponentCount {
            label = "pack \(label) · \(count)"
        }
        return label
    }

    private static func french(_ entry: Entry) -> String {
        guard let percent = entry.frPercent else { return "aucun" }
        return "\(percent) %"
    }

    private static func source(_ entry: Entry) -> String {
        guard let id = entry.nexusId else { return "—" }
        return "Nexus \(id)"
    }
}
