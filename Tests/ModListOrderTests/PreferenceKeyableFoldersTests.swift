import Testing
import Foundation
@testable import StarHubTHCore

/// X74 — quels dossiers une préférence peut désigner. La question n'est pas
/// « quelles identités sont installées » (à quoi `flattenedMods` répond) mais
/// « sur quelles lignes l'utilisateur a-t-il pu poser un réglage ».
struct PreferenceKeyableFoldersTests {
    private func mod(_ name: String, folder: String? = nil,
                     children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: children == nil ? "id.\(name)" : "",
                name: name, folderName: folder ?? name, version: "1.0",
                author: "A", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: true, dependencies: [],
                children: children, isGroup: children != nil)
    }

    @Test func aPackHeaderCanCarryAPreference() {
        // Le champ « identifiant Nexus » et le sélecteur de catégorie sont
        // offerts sur la fiche d'un pack : sa clé doit compter comme vivante.
        let mods = [mod("MonPack", children: [mod("Compo", folder: "MonPack/Compo")])]
        let folders = mods.preferenceKeyableFolders
        #expect(folders.contains("MonPack"))
        #expect(folders.contains("MonPack/Compo"))
        // L'écart avec l'ancienne règle, épinglé : c'est **elle** le défaut,
        // et un test qui ne le montre pas ne prouve rien.
        #expect(!Set(mods.flattenedMods.map(\.folderName)).contains("MonPack"))
    }

    @Test func aSimpleModIsCountedOnce() {
        #expect([mod("Automate")].preferenceKeyableFolders == ["Automate"])
    }

    @Test func anEmptyNameIsNeverAKey() {
        // Un en-tête fabriqué sans nom ne doit pas faire passer la clé vide
        // pour vivante — `stalePreferenceKeys` l'écarte déjà de son côté.
        let mods = [mod("Sans nom", folder: "", children: [mod("C", folder: "C")])]
        #expect(!mods.preferenceKeyableFolders.contains(""))
    }

    @Test func anEmptyParcYieldsNothing() {
        #expect([ModItem]().preferenceKeyableFolders.isEmpty)
    }
}
