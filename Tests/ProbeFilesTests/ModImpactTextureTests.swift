import Foundation
import Testing
@testable import StarHubTHCore

/// D4-T6 — la mémoire retenue en textures dans l'historique d'impact, sur une
/// session réelle (`make_texture_fixture.py`).
struct ModImpactTextureTests {
    private func side(inventory name: String) throws -> ProbeSide {
        let sessions = ProbeSessions.decode(timings: try Fixture.data("texture-timings.jsonl"),
                                            costs: try Fixture.data("texture-mod-costs.jsonl"))
        let inventory = ProbeInventory.decode(try Fixture.data(name))
        let sides = ProbePerformance.sides(sessions: sessions, launches: inventory.launches,
                                           changes: inventory.changes, measurements: [])
        return try #require(sides.first { $0.comparable.kept.count >= ModImpactSources.minimumKeptMinutes })
    }

    /// Avant 0.9.23, les textures des packs tombaient sous Content Patcher :
    /// la source compte, ses textures non.
    @Test func aProbeBeforeOnBehalfOfRecordsNoTextures() throws {
        let source = try #require(ModImpactSources.inGame(try side(inventory: "texture-inventory-real.jsonl")))
        #expect(!source.samples.isEmpty)
        #expect(source.samples.values.allSatisfy { $0.textureMB == nil })
        #expect(source.samples["vanilla"] == nil)
    }

    @Test func texturesJoinTheCostSampleAndKeepOwnersWithoutCode() throws {
        let side = try side(inventory: "texture-inventory-0.9.23.jsonl")
        let source = try #require(ModImpactSources.inGame(side))
        let keys = source.samples.keys.map { $0.lowercased() }
        #expect(Set(keys).count == keys.count)   // une ligne par mod, sans casse

        let cp = try #require(source.samples["Pathoschild.ContentPatcher"])
        #expect(cp.msPerSecond != nil)
        let cpMB = try #require(cp.textureMB)
        #expect(cpMB >= 788 && cpMB <= 803)      // 788,3 → 802,9 Mio sur la session

        let vanilla = try #require(source.samples["vanilla"])
        #expect(vanilla.fpsShare == nil && vanilla.allocShare == nil && vanilla.spikeShare == nil)
        #expect(try #require(vanilla.textureMB) > 90)
        #expect(vanilla.isNegligible)

        // Les parts de temps ne changent pas : les échantillons « textures
        // seules » n'en portent pas.
        #expect(abs(source.samples.values.compactMap(\.fpsShare).reduce(0, +) - 1) < 1e-9)
        #expect(!source.samples.keys.contains { $0.caseInsensitiveCompare(BenchmarkSides.probeId) == .orderedSame })
    }

    /// Un attributaire absent d'une minute relevée y compte 0 : sur les 24
    /// minutes réelles de la session, SpaceCore n'apparaît que dans les deux
    /// dernières — sa médiane est 0, pas sa taille quand il est là.
    @Test func anOwnerMissingFromMostMinutesWeighsZeroNotNothing() throws {
        let sessions = ProbeSessions.decode(timings: try Fixture.data("texture-timings.jsonl"), costs: nil)
        let minutes = try #require(sessions.sessions.first).minutes
            .map { ProbeComparableMinute(minute: $0, patchesMeasured: nil) }
        let present = minutes.filter { $0.minute.textureByMod?["spacechase0.SpaceCore"] != nil }.count
        #expect(present == 2 && minutes.count == 24)
        let textures = ModImpactSources.retainedTextureMB(minutes, probeVersion: "0.9.23")
        #expect(textures["spacechase0.SpaceCore"] == 0)
        #expect(try #require(textures["Pathoschild.ContentPatcher"]) > 780)
        #expect(ModImpactSources.retainedTextureMB(minutes, probeVersion: "0.9.22").isEmpty)
        #expect(ModImpactSources.retainedTextureMB(minutes, probeVersion: nil).isEmpty)
    }

    @Test func aContentPackHasTexturesButNoScore() throws {
        var history = ModImpactHistory()
        history.integrate(try #require(ModImpactSources.inGame(try side(inventory: "texture-inventory-0.9.23.jsonl"))))
        let vanillaSamples = try #require(history.samples["vanilla"])
        let stats = try #require(ModImpact.versionStats(vanillaSamples).first)
        #expect(!stats.hasTimings)
        #expect(stats.impactClass == nil)
        #expect(stats.textureSources == 1)
        #expect(stats.textureMB != nil)
        let cpSamples = try #require(history.samples["pathoschild.contentpatcher"])
        let cp = try #require(ModImpact.versionStats(cpSamples).first)
        #expect(cp.hasTimings && cp.textureMB != nil)
    }

    /// Les lignes : mods installés relevés ; le reliquat : tout le reste de
    /// la dernière session, jamais jeté.
    @Test func rowsAndRemainderAccountForEveryOwner() throws {
        var history = ModImpactHistory()
        let source = try #require(ModImpactSources.inGame(try side(inventory: "texture-inventory-0.9.23.jsonl")))
        history.integrate(source)
        func entry(_ id: String, enabled: Bool = true) throws -> ModImpactEntry {
            ModImpactEntry(id: id, modId: id, name: id, installedVersion: "0", isEnabled: enabled,
                           versions: ModImpact.versionStats(try #require(history.samples[id.lowercased()])))
        }
        let entries = [try entry("Cropgenics"), try entry("Pathoschild.ContentPatcher"),
                       try entry("Becks723.FontSettings", enabled: false)]
        let rows = ProbeTexturePresentation.rows(entries: entries)
        #expect(rows.map(\.id) == ["Pathoschild.ContentPatcher", "Cropgenics"])   // le plus lourd d'abord, actifs seuls
        #expect(rows.allSatisfy { $0.sourceCount == 1 && !$0.currentVersionMeasured })

        let installed = Set(entries.map { $0.modId.lowercased() })
        let remainder = try #require(ProbeTexturePresentation.remainder(history: history, installedIds: installed))
        #expect(remainder.owners.contains("vanilla"))
        #expect(!remainder.owners.contains { installed.contains($0) })
        let expected = source.samples
            .filter { !installed.contains($0.key.lowercased()) }
            .compactMap(\.value.textureMB).reduce(0, +)
        #expect(abs(remainder.mb - expected) < 1e-9)
    }

    @Test func noTexturesMeansNoRowsAndNoRemainder() throws {
        var history = ModImpactHistory()
        history.integrate(try #require(ModImpactSources.inGame(try side(inventory: "texture-inventory-real.jsonl"))))
        #expect(ProbeTexturePresentation.remainder(history: history, installedIds: []) == nil)
    }

    /// Un historique écrit avant D4-T6 (échantillon réel, sans `textureMB`)
    /// se relit : le champ manquant vaut `nil`.
    @Test func aSampleWrittenBeforeTexturesStillDecodes() throws {
        let json = #"{"date": 812580052.9289999, "kind": "launch", "loadShare": 0.00010816307399728417, "ms": 7.949999999999999, "sourceId": "2026-10-01T22:41:25.5097610+02:00|launch|2026-10-01T22:40:52.9298180+02:00", "version": "1.2.0"}"#
        let sample = try JSONDecoder().decode(ModImpactSample.self, from: Data(json.utf8))
        #expect(sample.textureMB == nil && sample.kind == .launch)
    }
}
