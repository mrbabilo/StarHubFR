import Foundation

/// Le **plan** d'une bascule de mod (REFACTORING §6, domaine Bascule) :
/// quel dossier amorcer, quel état viser, et quels dossiers basculer avec
/// lui quand le chaînage des dépendances est actif. Le calcul est pur —
/// « ce qui n'est pas à moi arrive en paramètre » (§3) : le parc (`mods`,
/// l'instantané du moment), le mod demandé et la préférence de chaînage
/// arrivent en valeurs. L'**application** — renommages sur disque, poids,
/// horodatages, republication — reste chez l'appelant.
///
/// Tout se raisonne en **dossiers de premier niveau** : un composant de pack
/// (`Pack/Enfant`) est d'abord ramené au dossier qui le porte, faute de quoi
/// le bouton « Activer » d'un enfant ne faisait rien, en silence.
struct TogglePlan: Equatable {

    /// Le dossier amorce — celui sur lequel l'utilisateur a cliqué, ramené
    /// à son dossier de premier niveau.
    let seedFolder: String
    /// `true` = activer, `false` = mettre en pause.
    let targetState: Bool
    /// Les dossiers à basculer, amorce comprise.
    let folders: Set<String>

    /// Construit le plan. `chain` bas la bascule d'un seul dossier ; `chain`
    /// haut active récursivement les dépendances **requises** manquantes ou
    /// en pause, et met en pause récursivement les mods actifs qui exigent
    /// le dossier amorce.
    static func make(mod: ModItem, mods: [ModItem], chain: Bool) -> TogglePlan {
        // Déjà premier niveau (mod seul ou en-tête de pack) → tel quel.
        // Sinon, résoudre le pack qui porte cet UniqueID — le même
        // rapprochement que la traversée des dépendances plus bas.
        let seedFolder: String = {
            if mods.contains(where: { $0.folderName == mod.folderName }) {
                return mod.folderName
            }
            return topLevelFolder(for: mod.uniqueId, in: mods) ?? mod.folderName
        }()

        // Re-dériver de l'instantané plutôt que de faire confiance à
        // `mod.isEnabled` — `mod` a été capturé par valeur à l'empilement
        // (voir `toggleMod`) : quand un appel empilé s'exécute enfin,
        // `mods` peut déjà refléter la bascule d'un appel antérieur.
        let currentIsEnabled = mods.first(where: { $0.folderName == seedFolder })?.isEnabled ?? mod.isEnabled
        let targetState = !currentIsEnabled

        var folders: Set<String> = [seedFolder]
        if chain {
            if targetState {
                folders.formUnion(enableChain(from: seedFolder, mods: mods))
            } else {
                folders.formUnion(disableChain(from: seedFolder, mods: mods, already: folders))
            }
        }
        return TogglePlan(seedFolder: seedFolder, targetState: targetState, folders: folders)
    }

    /// Retourne l'amorce : le dossier de premier niveau qui porte un
    /// UniqueID — mod seul, ou en-tête de pack dont un enfant déclare
    /// l'identifiant. `nil` si rien ne correspond.
    static func topLevelFolder(for uniqueId: String, in mods: [ModItem]) -> String? {
        for m in mods {
            if !m.isGroup && m.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame {
                return m.folderName
            } else if m.isGroup, let children = m.children {
                if children.contains(where: { $0.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame }) {
                    return m.folderName
                }
            }
        }
        return nil
    }

    /// Activer : toutes les dépendances **requises** manquantes ou en pause,
    /// transitivement. La traversée continue à travers des dépendances déjà
    /// actives (`visited`, distinct de la liste à basculer) pour qu'un mod
    /// en pause deux niveaux plus bas d'une chaîne déjà active soit
    /// quand même rattrapé.
    private static func enableChain(from seedFolder: String, mods: [ModItem]) -> Set<String> {
        var folders: Set<String> = []
        var queue = [seedFolder]
        var visited: Set<String> = [seedFolder]
        while !queue.isEmpty {
            let currentFolder = queue.removeFirst()
            let deps = dependencies(of: currentFolder, in: mods)

            for dep in deps where dep.isRequired {
                if let depFolder = topLevelFolder(for: dep.uniqueId, in: mods), !visited.contains(depFolder) {
                    visited.insert(depFolder)
                    let isDepFolderEnabled = mods.first(where: { $0.folderName == depFolder })?.isEnabled ?? false
                    if !isDepFolderEnabled {
                        folders.insert(depFolder)
                    }
                    queue.append(depFolder)
                }
            }
        }
        return folders
    }

    /// Mettre en pause : tous les mods **actifs** qui exigent le dossier
    /// amorce, transitivement. Un dépendant déjà en pause n'entre ni dans
    /// la liste ni dans la file.
    private static func disableChain(from seedFolder: String, mods: [ModItem],
                                     already: Set<String>) -> Set<String> {
        var folders: Set<String> = []
        var queue = [seedFolder]
        while !queue.isEmpty {
            let currentFolder = queue.removeFirst()

            var providedUniqueIds: [String] = []
            if let m = mods.first(where: { $0.folderName == currentFolder }) {
                if m.isGroup, let children = m.children {
                    providedUniqueIds = children.map { $0.uniqueId }
                } else {
                    providedUniqueIds = [m.uniqueId]
                }
            }

            for otherMod in mods where otherMod.isEnabled && !folders.contains(otherMod.folderName) {
                let otherDeps = dependencies(of: otherMod.folderName, in: mods)
                let requiresCurrent = otherDeps.contains { dep in
                    dep.isRequired && providedUniqueIds.contains { $0.caseInsensitiveCompare(dep.uniqueId) == .orderedSame }
                }
                if requiresCurrent {
                    folders.insert(otherMod.folderName)
                    queue.append(otherMod.folderName)
                }
            }
        }
        return folders
    }

    /// Toutes les dépendances d'un dossier de premier niveau (les enfants
    /// d'un pack s'additionnent).
    private static func dependencies(of folderName: String, in mods: [ModItem]) -> [ModDependency] {
        guard let m = mods.first(where: { $0.folderName == folderName }) else { return [] }
        if m.isGroup, let children = m.children {
            return children.flatMap { $0.dependencies }
        }
        return m.dependencies
    }

    /// La republication en mémoire : seuls les dossiers basculés changent
    /// d'état, et les enfants d'un pack suivent leur en-tête. Le disque,
    /// lui, a déjà été renommé par l'appelant.
    static func flipped(_ mods: [ModItem], folders: Set<String>, target: Bool) -> [ModItem] {
        mods.map { mod in
            guard folders.contains(mod.folderName) else { return mod }
            var m = mod
            m.isEnabled = target
            if m.isGroup, var children = m.children {
                for i in children.indices { children[i].isEnabled = target }
                m.children = children
            }
            return m
        }
    }
}
