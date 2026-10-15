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
                        #expect(HelpLink.resolve(link, in: sections) != .ignored,
                                "\(name) : lien mort \(link.relativeString)")
                    }
                }
            }
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

    @Test func chaquePageMeneAUneSectionQuiExiste() {
        let pages: [SidebarDestination] = [.home, .mods, .discover, .updates, .frenchTranslations,
                                           .profiles, .saves, .systemAlerts, .quarantine, .backups,
                                           .maintenance, .logs, .settings, .appChangelog]
        for page in pages {
            for diagnostics in DiagnosticsSegment.allCases {
                for alerts in AlertsSegment.allCases {
                    let id = HelpTopic.section(for: page, diagnosticsSegment: diagnostics, alertsSegment: alerts)
                    #expect(HelpTopic.sectionIDs.contains(id), "\(page) → \(id)")
                }
            }
        }
    }

    @Test func lesOngletsChoisissentLaSection() {
        #expect(HelpTopic.section(for: .logs, diagnosticsSegment: .performance, alertsSegment: .alerts) == "performance")
        #expect(HelpTopic.section(for: .logs, diagnosticsSegment: .health, alertsSegment: .alerts) == "troubleshooting")
        #expect(HelpTopic.section(for: .systemAlerts, diagnosticsSegment: .health, alertsSegment: .keybinds) == "shortcuts")
        #expect(HelpTopic.section(for: .systemAlerts, diagnosticsSegment: .health, alertsSegment: .conflicts) == "troubleshooting")
    }
}
