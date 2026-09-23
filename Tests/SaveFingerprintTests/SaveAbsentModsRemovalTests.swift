import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T10 — suppression des clés smapi/mod-data des mods disparus.
/// Forme mesurée sur Zofia (2026-09-23), 35/35 items réguliers.
@Suite struct SaveAbsentModsRemovalTests {
    private func mod(_ id: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: id, folderName: id, version: "1",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }
    private func item(_ clé: String, _ valeur: String) -> String {
        "<item><key><string>\(clé)</string></key><value><string>\(valeur)</string></value></item>"
    }
    private let préfixe = "<modData>"

    @Test("Une clé d'uid disparu est supprimée, avec sa clé complète rapportée")
    func absentUidIsRemoved() {
        let original = préfixe + item("smapi/mod-data/aloofllama.giftdiscovery/state", "{}") + "</modData>"
        let r = SaveAbsentModsRemoval.removing(from: original, mods: [])
        #expect(r.removedKeys == ["smapi/mod-data/aloofllama.giftdiscovery/state"])
        #expect(r.untouchedKeys.isEmpty)
        #expect(r.content == "<modData></modData>")
    }

    @Test("Un uid installé est conservé — texte identique octet pour octet")
    func installedUidIsKeptByteIdentical() {
        let original = préfixe + item("smapi/mod-data/spacechase0.spacecore/skills", "1") + "</modData>"
        let r = SaveAbsentModsRemoval.removing(from: original, mods: [mod("SpaceChase0.SpaceCore")])
        #expect(r.removedKeys.isEmpty && r.untouchedKeys.isEmpty)
        #expect(Data(r.content.utf8) == Data(original.utf8))
    }

    @Test("Un mod en pause n'est pas disparu ; la casse est ignorée")
    func pausedModKeysAreKept() {
        let original = préfixe + item("smapi/mod-data/bindicle.dayswork/data", "x") + "</modData>"
        let r = SaveAbsentModsRemoval.removing(from: original, mods: [mod("Bindicle.Dayswork", enabled: false)])
        #expect(r.removedKeys.isEmpty)
        #expect(Data(r.content.utf8) == Data(original.utf8))
    }

    @Test("Plusieurs clés du même uid disparu partent toutes")
    func severalKeysOfSameUidAllGo() {
        let original = préfixe
            + item("smapi/mod-data/a.a/x", "1") + item("smapi/mod-data/keep.k/y", "2")
            + item("smapi/mod-data/a.a/z", "3") + "</modData>"
        let r = SaveAbsentModsRemoval.removing(from: original, mods: [mod("Keep.K")])
        #expect(r.removedKeys == ["smapi/mod-data/a.a/x", "smapi/mod-data/a.a/z"])
        #expect(r.content == préfixe + item("smapi/mod-data/keep.k/y", "2") + "</modData>")
    }

    @Test("Un item de forme atypique est laissé et compté, pas supprimé")
    func atypicalItemIsLeftAndCounted() {
        // la clé portée n'est pas suivie de la forme régulière attendue
        let original = préfixe + "<item><key><string>smapi/mod-data/odd.o/broken</string></item>" + "</modData>"
        let r = SaveAbsentModsRemoval.removing(from: original, mods: [])
        #expect(r.removedKeys.isEmpty)
        #expect(r.untouchedKeys == ["smapi/mod-data/odd.o/broken"])
        #expect(Data(r.content.utf8) == Data(original.utf8))
    }

    @Test("Un uid absorbé par un mod installé (legacy-migrated) n'est pas retiré")
    func legacyMigratedUidIsKept() {
        // Mesuré : walletautopetter → WalletTools. La section ne le liste
        // pas ; le nettoyage ne doit pas le retirer non plus.
        let original = préfixe
            + item("smapi/mod-data/thale.wallettools/legacy-migrated-thale.petter-v1", "1")
            + item("smapi/mod-data/thale.petter/state", "2") + "</modData>"
        let r = SaveAbsentModsRemoval.removing(from: original, mods: [mod("Thale.WalletTools")])
        #expect(r.removedKeys.isEmpty)
        #expect(Data(r.content.utf8) == Data(original.utf8))
    }

    @Test("Le BOM de tête traverse la suppression")
    func leadingBOMIsKept() {
        let original = "\u{FEFF}" + préfixe + item("smapi/mod-data/gone.g/k", "v") + "</modData>"
        let r = SaveAbsentModsRemoval.removing(from: original, mods: [])
        #expect(r.content == "\u{FEFF}<modData></modData>")
    }

    @Test("Aucune clé smapi → identité octet pour octet")
    func noMatchLeavesBytesIdentical() {
        let original = "<save><player><name>Zofia</name></player></save>"
        let r = SaveAbsentModsRemoval.removing(from: original, mods: [])
        #expect(Data(r.content.utf8) == Data(original.utf8))
        #expect(r.removedKeys.isEmpty && r.untouchedKeys.isEmpty)
    }
}
