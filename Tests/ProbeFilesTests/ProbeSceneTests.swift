import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeSceneTests {
    /// Une ligne de minute avec ou sans `Scene` (clés PascalCase du
    /// producteur, toujours décodées par le décodeur du dépôt).
    private func minute(scene: [String: Int]?) throws -> ProbeMinute {
        let sceneJson = scene.map { pairs in
            "{" + pairs.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",") + "}"
        } ?? "null"
        let json = """
        {"Session":"s","At":"2026-10-05T18:00:00.0000000+02:00","WallSeconds":60,"Fps":30,
         "FrameInterval":{"Count":45,"Avg":30,"P50":30,"P99":50,"Max":60},
         "HeapMB":4000,"LoadedMods":289,"Location":"Farm",
         "Tick":{"Count":1000,"Avg":20,"P50":20,"P99":40,"Max":50},
         "GameTime":650,"Scene":\(sceneJson)}
        """
        return try ProbeJSON.decoder().decode(ProbeMinute.self, from: Data(json.utf8))
    }

    /// Le champ se décode et reste `nil` sur une ligne qui ne le porte pas
    /// (sondes antérieures à 0.9.21).
    @Test func decodesSceneAndToleratesAbsence() throws {
        let scene = try #require(minute(scene: ["npcs": 3, "lights": 48]).scene)
        #expect(scene["npcs"] == 3)
        #expect(scene["lights"] == 48)
        let absent = try minute(scene: nil)
        #expect(absent.scene == nil)
        #expect(!ProbeScene.hasData([absent]))
    }

    /// Médiane par compteur, compteur jamais mesuré absent du résultat.
    @Test func mediansSkipUnmeasuredCounters() throws {
        let a = try minute(scene: ["furniture": 312])
        let b = try minute(scene: ["furniture": 314])
        let medians = ProbeScene.medians([a, b])
        #expect(medians["furniture"] == 313)
        #expect(medians["lights"] == nil)
    }

    /// Une scène qui ne bouge pas ne dit rien ; une scène qui sépare (écart
    /// net, quartiles disjoints) donne la différence.
    @Test func differencesNeedNetChange() throws {
        var stable: [ProbeMinute] = []
        for _ in 0..<6 { stable.append(try minute(scene: ["furniture": 300])) }
        #expect(ProbeScene.differences(before: stable, after: stable).isEmpty)

        var before: [ProbeMinute] = []
        var after: [ProbeMinute] = []
        for _ in 0..<6 {
            before.append(try minute(scene: ["furniture": 300, "lights": 48]))
            after.append(try minute(scene: ["furniture": 450, "lights": 48]))
        }
        let differences = ProbeScene.differences(before: before, after: after)
        #expect(differences.count == 1)
        let furniture = try #require(differences.first)
        #expect(furniture.key == "furniture")
        #expect(furniture.medianBefore == 300)
        #expect(furniture.medianAfter == 450)
        #expect(furniture.percent == 50)
    }

    /// Moins de cinq minutes d'un côté : le verdict commun est « pas assez »,
    /// aucune différence annoncée.
    @Test func differencesNeedEnoughMinutes() throws {
        var before: [ProbeMinute] = []
        var after: [ProbeMinute] = []
        for _ in 0..<4 { before.append(try minute(scene: ["furniture": 300])) }
        for _ in 0..<6 { after.append(try minute(scene: ["furniture": 450])) }
        #expect(ProbeScene.differences(before: before, after: after).isEmpty)
    }
}
