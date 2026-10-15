import Foundation
import Testing
@testable import StarHubTHCore

@Suite("Guide utilisateur — vrais fichiers, recherche, pages")
struct HelpGuideContentTests {
    /// Tests/HelpGuideTests/<fichier> → racine du dépôt.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func guide(_ name: String) throws -> [HelpSection] {
        HelpGuide.parse(try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8))
    }

    @Test func lesDeuxGuidesOntLesDouzeSectionsDansLOrdre() throws {
        #expect(try Self.guide("GUIDE.md").map(\.id) == HelpTopic.sectionIDs)
        #expect(try Self.guide("GUIDE_EN.md").map(\.id) == HelpTopic.sectionIDs)
    }

    @Test func chaqueSectionALeTexte() throws {
        for name in ["GUIDE.md", "GUIDE_EN.md"] {
            for section in try Self.guide(name) {
                #expect(!section.blocks.isEmpty, "\(name) : \(section.id) est vide")
            }
        }
    }

    @Test func lesLiensInternesDesGuidesMenentQuelquePart() throws {
        for name in ["GUIDE.md", "GUIDE_EN.md"] {
            let sections = try Self.guide(name)
            var checked = 0
            for section in sections {
                // Les liens vivent aussi dans les listes (section 2 → section 10).
                let texts = section.blocks.flatMap { block -> [String] in
                    switch block {
                    case .paragraph(let text): return [text]
                    case .bulletList(let items), .numberedList(let items): return items
                    case .code: return []
                    }
                }
                for text in texts where text.contains("](#") {
                    let attributed = try AttributedString(
                        markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
                    for link in attributed.runs.compactMap(\.link) where link.relativeString.hasPrefix("#") {
                        checked += 1
                        #expect(HelpLink.resolve(link, in: sections) != .ignored,
                                "\(name) : lien mort \(link.relativeString)")
                    }
                }
            }
            #expect(checked > 0, "\(name) : aucun lien interne vérifié")
        }
    }

    @Test func laRechercheIgnoreAccentsEtCasse() throws {
        let sections = try Self.guide("GUIDE.md")
        let found = HelpSearch.filter(sections, query: "MISES A JOUR")
        #expect(found.contains { $0.id == "updates" })
    }

    @Test func uneRechercheVideRendTout() throws {
        let sections = try Self.guide("GUIDE.md")
        #expect(HelpSearch.filter(sections, query: "  ") == sections)
    }

    @Test func uneRechercheSansResultatRendRien() throws {
        #expect(HelpSearch.filter(try Self.guide("GUIDE.md"), query: "zzzintrouvable").isEmpty)
    }

    /// Le tableau de la spec §3, exact : (page, segment diagnostics, segment alertes) → section.
    @Test func chaquePageMeneALaSectionDeLaSpec() {
        let table: [(SidebarDestination, DiagnosticsSegment, AlertsSegment, String)] = [
            (.home, .health, .alerts, "first-launch"),
            (.settings, .health, .alerts, "first-launch"),
            (.appChangelog, .health, .alerts, "first-launch"),
            (.mods, .health, .alerts, "install"),
            (.discover, .health, .alerts, "install"),
            (.updates, .health, .alerts, "updates"),
            (.frenchTranslations, .health, .alerts, "translate"),
            (.profiles, .health, .alerts, "profiles"),
            (.saves, .health, .alerts, "recover"),
            (.backups, .health, .alerts, "recover"),
            (.maintenance, .health, .alerts, "recover"),
            (.quarantine, .health, .alerts, "recover"),
            (.systemAlerts, .health, .alerts, "troubleshooting"),
            (.systemAlerts, .health, .conflicts, "troubleshooting"),
            (.systemAlerts, .health, .keybinds, "shortcuts"),
            (.logs, .health, .alerts, "troubleshooting"),
            (.logs, .journal, .alerts, "troubleshooting"),
            (.logs, .performance, .alerts, "performance"),
        ]
        for (page, diagnostics, alerts, expected) in table {
            #expect(HelpTopic.section(for: page, diagnosticsSegment: diagnostics, alertsSegment: alerts) == expected,
                    "\(page) \(diagnostics) \(alerts)")
        }
    }

    @Test func uneRechercheTrouveUnMotDuCorpsSeulement() throws {
        // « colorfulvolume » : dans le corps de « pause », dans aucun titre.
        let sections = try Self.guide("GUIDE.md")
        let word = "colorfulvolume"
        #expect(!sections.contains { CommandPaletteSearch.fold($0.title).contains(word) })
        let found = HelpSearch.filter(sections, query: word)
        #expect(found.contains { $0.id == "pause" })
        #expect(found.allSatisfy { CommandPaletteSearch.fold($0.searchText).contains(word) })
    }

    @Test func laCibleDUnLienNeSuffitPasALaRecherche() throws {
        // L'ancre `#10-retrouver-…` ne doit plus faire remonter la section qui la cite.
        let found = HelpSearch.filter(try Self.guide("GUIDE.md"), query: "retrouver")
        #expect(!found.contains { $0.id == "install" })
    }

    @Test func lesOngletsChoisissentLaSection() {
        #expect(HelpTopic.section(for: .logs, diagnosticsSegment: .performance, alertsSegment: .alerts) == "performance")
        #expect(HelpTopic.section(for: .logs, diagnosticsSegment: .health, alertsSegment: .alerts) == "troubleshooting")
        #expect(HelpTopic.section(for: .systemAlerts, diagnosticsSegment: .health, alertsSegment: .keybinds) == "shortcuts")
        #expect(HelpTopic.section(for: .systemAlerts, diagnosticsSegment: .health, alertsSegment: .conflicts) == "troubleshooting")
    }
}
