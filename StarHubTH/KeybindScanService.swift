import Foundation
import SwiftUI

/// Lit les `config.json` du profil actif et publie le rapport de
/// raccourcis. Aucune écriture — le scan n'ouvre aucun droit sur les
/// dossiers 0555 du parc (spec §8).
@MainActor
final class KeybindScanService: ObservableObject {
    @Published private(set) var report: KeybindScanner.KeybindReport?
    @Published private(set) var isScanning = false

    /// Signature du dernier scan **effectivement lancé** (pas seulement
    /// demandé) : `gameDir` plus l'identité et l'état actif de chaque
    /// candidat. `scanIfNeeded` s'en sert pour savoir si le parc a bougé
    /// depuis ; elle n'est mise à jour que dans `scan`, au moment où il
    /// franchit ses propres gardes — un appel refusé (déjà en cours,
    /// dossier de jeu vide) ne doit pas figer la signature sur un scan qui
    /// n'a jamais eu lieu (ronde de revue 2, constat 3).
    private var lastScannedSignature: Int?

    /// Un scan demandé pendant qu'un autre tourne, à rejouer à sa fin (X66).
    ///
    /// `scan` refuse quand `isScanning` : la demande était simplement perdue.
    /// Sans conséquence tant que le seul appelant était le `.onAppear` d'une
    /// section, mais les écritures de `config.json` (restauration d'une
    /// sauvegarde, bascule de profil, récupération d'un fichier) demandent un
    /// rescan à des moments qu'elles ne choisissent pas — et la lecture qui
    /// tourne à ce moment-là voit un état d'avant l'écriture. Le rapport
    /// resterait périmé jusqu'à la prochaine visite de l'onglet.
    ///
    /// On garde **l'état demandé**, pas un simple drapeau : rejouer avec les
    /// arguments du scan en cours relirait bien le disque, mais sur la liste
    /// de candidats d'avant — et poserait `lastScannedSignature` pour un parc
    /// jamais lu. `scanIfNeeded` se croirait alors à jour sur un état qu'il
    /// n'a pas vu. C'est le cas d'une bascule de profil, qui bouge le parc
    /// *puis* réécrit des `config.json`.
    private var pendingRescan: (mods: [ModItem], gameDir: String)?

    // `nonisolated`, comme `BisectionRunner.init(vm:)` : la propriété qui
    // porte ce service sur `StarHubTHViewModel` (`keybindScanService`) est
    // instanciée depuis une classe qui n'est elle-même pas `@MainActor`.
    // L'init implicite d'une classe `@MainActor` serait isolée et
    // échouerait à la compilation depuis ce contexte (ronde de revue 1,
    // constat 1) ; ce corps vide ne fait qu'accepter les valeurs par
    // défaut déjà posées ci-dessus.
    nonisolated init() {}

    /// Appelé au `onAppear` de la section, à la place d'une garde
    /// `report == nil` : cette garde-là ne rescannait plus jamais après le
    /// tout premier scan de la vie de l'app, donc un mod activé entre deux
    /// visites de l'onglet restait absent du rapport sans que rien ne le
    /// signale (ronde de revue 2, constat 3). Ici, un rescan implicite n'a
    /// lieu que si le parc (ou `gameDir`) a changé depuis le dernier scan
    /// lancé ; le bouton « Relancer l'analyse » reste, lui, inconditionnel
    /// — il appelle `scan` directement.
    func scanIfNeeded(mods: [ModItem], gameDir: String) {
        guard !isScanning, !gameDir.isEmpty else { return }
        let signature = signature(of: candidates(in: mods), gameDir: gameDir)
        guard report == nil || signature != lastScannedSignature else { return }
        scan(mods: mods, gameDir: gameDir)
    }

    func scan(mods: [ModItem], gameDir: String) {
        guard !isScanning else {
            // Ne pas perdre la demande : la relecture en cours a pu commencer
            // avant l'écriture qui motive celle-ci. La dernière demande gagne
            // — c'est celle qui décrit l'état le plus récent.
            pendingRescan = (mods, gameDir)
            return
        }
        // Sans dossier de jeu, tous les chemins seraient construits sur « » :
        // le scan ne lirait rien et rendrait un rapport à zéro conflit — un
        // vert mensonger. On ne scanne pas, la vue le dit.
        guard !gameDir.isEmpty else { return }
        isScanning = true
        let candidates = candidates(in: mods)
        lastScannedSignature = signature(of: candidates, gameDir: gameDir)

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
            if let pending = self.pendingRescan {
                self.pendingRescan = nil
                self.scan(mods: pending.mods, gameDir: pending.gameDir)
            }
        }
    }

    /// Aplatir les packs : un composant a son propre config.json.
    /// `flattenedMods` plutôt qu'un dépliage réécrit ici : ce dépliage
    /// existait en 22 copies divergentes dans 10 fichiers avant d'être
    /// unifié (voir son doc comment). Le filtre garde `!isGroup` parce que
    /// l'unification ne déplie qu'un niveau — un pack imbriqué dans un pack
    /// arrive encore ici comme une ligne de groupe. Partagé entre `scan` et
    /// `scanIfNeeded` : les deux doivent juger le même lot.
    private func candidates(in mods: [ModItem]) -> [ModItem] {
        mods.flattenedMods.filter { !$0.isGroup && $0.hasConfigFile }
    }

    /// Signature bon marché de ce qu'un scan verrait : `gameDir` plus
    /// `folderName`/`isEnabled` de chaque candidat, combinés dans un `Int`
    /// via `Hasher` plutôt qu'une grande chaîne concaténée — le parc fait
    /// environ 900 entrées.
    private func signature(of candidates: [ModItem], gameDir: String) -> Int {
        var hasher = Hasher()
        hasher.combine(gameDir)
        for mod in candidates {
            hasher.combine(mod.folderName)
            hasher.combine(mod.isEnabled)
        }
        return hasher.finalize()
    }
}
