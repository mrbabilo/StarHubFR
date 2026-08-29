import Foundation
import SwiftUI

/// Lit les `config.json` du profil actif et publie le rapport de
/// raccourcis. Aucune écriture — le scan n'ouvre aucun droit sur les
/// dossiers 0555 du parc (spec §8).
@MainActor
final class KeybindScanService: ObservableObject {
    @Published private(set) var report: KeybindScanner.KeybindReport?
    @Published private(set) var isScanning = false

    func scan(mods: [ModItem], gameDir: String) {
        guard !isScanning else { return }
        // Sans dossier de jeu, tous les chemins seraient construits sur « » :
        // le scan ne lirait rien et rendrait un rapport à zéro conflit — un
        // vert mensonger. On ne scanne pas, la vue le dit.
        guard !gameDir.isEmpty else { return }
        isScanning = true
        // Aplatir les packs : un composant a son propre config.json.
        // `flattenedMods` plutôt qu'un dépliage réécrit ici : ce dépliage
        // existait en 22 copies divergentes dans 10 fichiers avant d'être
        // unifié (voir son doc comment). Le filtre garde `!isGroup` parce que
        // l'unification ne déplie qu'un niveau — un pack imbriqué dans un
        // pack arrive encore ici comme une ligne de groupe.
        let candidates = mods.flattenedMods.filter { !$0.isGroup && $0.hasConfigFile }

        Task {
            let inputs: [KeybindScanner.ModScan] = await Task.detached(priority: .userInitiated) {
                // Chemin copié de ModConfigEditorView.configPath — une seule
                // construction pour actifs et en pause (le point est dans
                // physicalFolderName).
                let base = (gameDir as NSString).appendingPathComponent("Mods")
                return candidates.map { mod -> KeybindScanner.ModScan in
                    let modPath = (base as NSString).appendingPathComponent(mod.physicalFolderName)
                    let configPath = (modPath as NSString).appendingPathComponent("config.json")
                    let tree: ConfigJSONTree.Value
                    if let data = FileManager.default.contents(atPath: configPath),
                       let text = String(data: data, encoding: .utf8),
                       let parsed = ConfigJSONTree.parse(text) {
                        tree = parsed
                    } else {
                        tree = .object(ConfigJSONTree.Object([]))
                    }
                    // `folderName` comme id, pas `name` : le scanner déduplique
                    // les collisions par modID, et deux mods distincts peuvent
                    // porter le même nom d'affichage (Swim, installé deux fois
                    // sur ce parc). `folderName` est l'id de ModItem — unique,
                    // logique (le point de pause est dans physicalFolderName)
                    // et chemisé `Pack/Composant` pour un composant. Pas
                    // `uniqueId` : 111 mods du parc n'en ont pas, et leurs
                    // chaînes vides fusionneraient en une seule identité.
                    return .init(id: mod.folderName, name: mod.name,
                                 isActive: mod.isEnabled, tree: tree)
                }
            }.value
            self.report = KeybindScanner.report(mods: inputs)
            self.isScanning = false
        }
    }
}
