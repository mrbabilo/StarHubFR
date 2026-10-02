import Foundation

/// C4-T13 — le rapport de raccourcis en **Markdown** daté, pour l'export.
///
/// Le rapport est consultatif et vit à l'écran ; l'export répond au geste
/// « le montrer à quelqu'un » — un fil de discussion, un rapport de bug, un
/// autre joueur. Pur : le texte seul arrive en paramètre, l'écriture du
/// fichier reste à l'appelant (panneau d'enregistrement).
///
/// Les sections vides ne s'écrivent pas : un rapport sans conflit ne dit pas
/// « conflits : aucun » quatre fois, il donne l'inventaire et le compte
/// scanné — la même honnêteté que l'écran (un vert ne sort que sur un lot
/// compris).
public enum KeybindReportExport {

    /// Date ISO locale, pour le titre du document.
    public static func markdown(report: KeybindScanner.KeybindReport,
                                generatedAt: Date) -> String {
        markdown(report: report, generatedAt: generatedAt, formatter: dateFormatter)
    }

    public static func markdown(report: KeybindScanner.KeybindReport,
                                generatedAt: Date,
                                formatter: DateFormatter) -> String {
        var out: [String] = []
        out.append("# Rapport des raccourcis")
        out.append("")
        out.append("_\(report.scannedMods) mods scannés · \(report.keybindCount) raccourcis liés · généré le \(formatter.string(from: generatedAt)) par StarHubFR._")
        out.append("")

        section("Collisions clavier", into: &out) {
            report.collisions.map { collision($0) }
        }
        section("Collisions manette", into: &out) {
            report.gamepadCollisions.map { collision($0) }
        }
        if !report.gameConflicts.isEmpty {
            section("Conflits avec les contrôles du jeu", into: &out) {
                report.gameConflicts.map { conflict in
                    "- **\(conflict.control.name)** — " + usesLine(conflict.uses)
                }
            }
        }
        if !report.subsetOverlaps.isEmpty {
            section("Co-déclenchements (geste long)", into: &out) {
                report.subsetOverlaps.map { overlap in
                    "- **\(overlap.subset.display)** ⊂ **\(overlap.superset.display)** — " + usesLine(overlap.uses)
                }
            }
        }
        if !report.latentCollisions.isEmpty {
            section("Collisions latentes (au moins un mod en pause)", into: &out) {
                report.latentCollisions.map { collision($0) }
            }
        }
        if !report.unrecognized.isEmpty {
            section("Raccourcis non reconnus", into: &out) {
                report.unrecognized.map { raw in
                    "- \(raw.modName) · `\(raw.keyPath.joined(separator: "."))` = `\(raw.raw)`"
                }
            }
        }

        // L'inventaire, trié par mod : la partie « liste de tous les
        // raccourcis », qui se lit même quand rien ne cloche.
        section("Tous les réglages liés", into: &out) {
            guard !report.settings.isEmpty else { return [] }
            var rows = ["| Mod | Réglage | Combinaison | État |",
                        "|---|---|---|---|"]
            for setting in report.settings.sorted(by: {
                $0.modName.localizedStandardCompare($1.modName) == .orderedAscending
            }) {
                let combo = setting.combos.isEmpty
                    ? "None"
                    : setting.combos.map(\.display).joined(separator: " / ")
                let state = setting.hasConflict ? "conflit" : (setting.isUnassigned ? "non assigné" : "lié")
                    rows.append("| \(setting.modName) | `\(setting.keyPath.joined(separator: "."))` | \(combo) | \(state) |")
            }
            return rows
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// `DateFormatter` figé en `en_US_POSIX` : la date d'un export part dans
    /// des échanges, elle doit se lire pareil partout.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static func section(_ title: String, into out: inout [String],
                                lines: () -> [String]) {
        let body = lines()
        guard !body.isEmpty else { return }
        out.append("## \(title)")
        out.append("")
        out.append(contentsOf: body)
        out.append("")
    }

    private static func collision(_ collision: KeybindScanner.KeybindCollision) -> String {
        "- **\(collision.combo.display)** — " + usesLine(collision.uses)
    }

    /// « Mod A (`chemin`), Mod B (en pause, `chemin`) ».
    private static func usesLine(_ uses: [KeybindScanner.ModUse]) -> String {
        uses.map { use in
            let pause = use.isActive ? "" : "en pause, "
            return "\(use.modName) (\(pause)`\(use.keyPath.joined(separator: "."))`)"
        }
        .joined(separator: ", ")
    }
}

extension DateFormatter {
    /// « 2026-10-02-1832 » — dans un nom de fichier, trié par date partout.
    static func posixStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}
