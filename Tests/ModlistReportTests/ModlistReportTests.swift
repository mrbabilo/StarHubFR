import Testing
import Foundation
@testable import StarHubTHCore

/// E2-T1 — le rapport de modlist exportable : les anomalies en tête, une
/// ligne par mod, deux formats (Markdown compact à coller, HTML complet à
/// archiver). Un rapport propre n'écrit pas de section vide.
struct ModlistReportTests {

    private func entry(name: String = "Alpha",
                       version: String = "1.0.0",
                       paused: Bool = false,
                       packComponents: Int? = nil,
                       frPercent: Int? = nil,
                       nexusId: String? = nil,
                       anomaly: String? = nil,
                       anomalyIsError: Bool = false) -> ModlistReport.Entry {
        .init(name: name, version: version, isPaused: paused,
              packComponentCount: packComponents, frPercent: frPercent,
              nexusId: nexusId, anomalyReason: anomaly,
              anomalyIsError: anomalyIsError)
    }

    // MARK: - Comptes d'en-tête

    @Test func headerCounts() {
        let md = ModlistReport.compact(entries: [
            entry(name: "Alpha", frPercent: 82, nexusId: "191"),
            entry(name: "Beta", paused: true),
            entry(name: "Gamma", anomaly: "dépendance manquante", anomalyIsError: true),
        ], generatedAt: Date(timeIntervalSince1970: 0))
        #expect(md.contains("# Rapport de la liste de mods"))
        #expect(md.contains("3 mods"))
        #expect(md.contains("1 anomalie"))
        #expect(md.contains("1 en pause"))
        #expect(md.contains("1 en français"))
        #expect(md.contains("généré le 1970-01-01"))
        #expect(md.contains("StarHubFR"))
    }

    // MARK: - Anomalies en tête, erreurs avant avertissements

    @Test func anomaliesBeforeInventoryAndErrorsFirst() {
        let md = ModlistReport.compact(entries: [
            entry(name: "Zeta", anomaly: "doublon ×2", anomalyIsError: false),
            entry(name: "Alpha", anomaly: "dépendance manquante", anomalyIsError: true),
            entry(name: "Omega"),
        ], generatedAt: Date())
        let anomalies = try! #require(md.range(of: "## Anomalies")).lowerBound
        let inventory = try! #require(md.range(of: "## Inventaire")).lowerBound
        #expect(anomalies < inventory)
        let errorRow = try! #require(md.range(of: "dépendance manquante")).lowerBound
        let warningRow = try! #require(md.range(of: "doublon ×2")).lowerBound
        #expect(errorRow < warningRow)
    }

    @Test func noAnomalySectionWhenAllHealthy() {
        let md = ModlistReport.compact(entries: [entry(name: "Alpha")], generatedAt: Date())
        #expect(!md.contains("## Anomalies"))
    }

    // MARK: - Ligne d'inventaire

    @Test func inventoryRowFields() {
        let md = ModlistReport.compact(entries: [
            entry(name: "Alpha", version: "1.2.3", frPercent: 82, nexusId: "191"),
        ], generatedAt: Date())
        #expect(md.contains("| Alpha | 1.2.3 | actif | 82 % | Nexus 191 |"))
    }

    @Test func pausedAndPackRows() {
        let md = ModlistReport.compact(entries: [
            entry(name: "Mon Pack", version: "2.0", paused: true, packComponents: 3),
            entry(name: "Solo", paused: true),
        ], generatedAt: Date())
        #expect(md.contains("| Mon Pack | 2.0 | pack en pause · 3 |"))
        #expect(md.contains("| Solo | 1.0.0 | en pause |"))
    }

    @Test func missingSourceAndFrench() {
        let md = ModlistReport.compact(entries: [
            entry(name: "SansId"),
        ], generatedAt: Date())
        #expect(md.contains("| SansId | 1.0.0 | actif | aucun | — |"))
    }

    // MARK: - Raison d'anomalie, composée depuis ModAnomaly

    @Test func reasonComposition() {
        let counts = ModAnomaly(severity: .error, errorCount: 2, warningCount: 1,
                                hasDependencyIssue: true, isUnloadable: true,
                                duplicate: .dormant(folders: ["a", "b", "c"]),
                                compatibility: .broken, renamed: nil)
        let reason = ModlistReport.reason(for: counts)
        #expect(reason.contains("2 erreurs"))
        #expect(reason.contains("1 avertissement"))
        #expect(reason.contains("dépendance manquante"))
        #expect(reason.contains("manifeste sans identifiant"))
        #expect(reason.contains("doublon ×3"))
        #expect(reason.contains("cassé (smapi.io)"))
        #expect(reason.contains(" · "))
    }

    @Test func reasonWarningOnly() {
        let light = ModAnomaly(severity: .warning, errorCount: 0, warningCount: 0,
                               hasDependencyIssue: false, isUnloadable: false,
                               compatibility: .abandoned)
        let reason = ModlistReport.reason(for: light)
        #expect(reason.contains("abandonné (smapi.io)"))
        #expect(!reason.contains("erreur"))
        #expect(!reason.contains("avertissement"))
    }

    // MARK: - HTML complet

    @Test func htmlFullContainsSameData() {
        let html = ModlistReport.html(entries: [
            entry(name: "Alpha", version: "1.2.3", frPercent: 82, nexusId: "191",
                  anomaly: "dépendance manquante", anomalyIsError: true),
            entry(name: "Beta", paused: true),
        ], generatedAt: Date(timeIntervalSince1970: 0))
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("lang=\"fr\""))
        #expect(html.contains("2 mods"))
        #expect(html.contains("Alpha"))
        #expect(html.contains("82 %"))
        #expect(html.contains("Nexus 191"))
        #expect(html.contains("dépendance manquante"))
        #expect(html.contains("en pause"))
        #expect(html.contains("généré le 1970-01-01"))
    }
}

/// Les noms et versions viennent des manifestes : rien n'empêche un auteur
/// d'y mettre `<`, `&` ou `|`. Échappés, ils ne cassent ni le tableau HTML
/// ni le tableau Markdown.
struct ModlistReportEscapingTests {
    private let entry = ModlistReport.Entry(
        name: "A <b>&</b> | B", version: "1.0|beta", isPaused: false,
        packComponentCount: nil, frPercent: nil, nexusId: nil,
        anomalyReason: "manifeste <illisible>", anomalyIsError: true)

    @Test func htmlCellsAreEscaped() {
        let html = ModlistReport.html(entries: [entry], generatedAt: Date(timeIntervalSince1970: 0))
        #expect(html.contains("A &lt;b&gt;&amp;&lt;/b&gt; | B"))
        #expect(html.contains("manifeste &lt;illisible&gt;"))
        #expect(!html.contains("<b>&</b>"))
    }

    @Test func markdownCellsEscapeThePipe() {
        let md = ModlistReport.compact(entries: [entry], generatedAt: Date(timeIntervalSince1970: 0))
        #expect(md.contains("| A <b>&</b> \\| B |"))
        #expect(md.contains("| 1.0\\|beta |"))
    }
}

