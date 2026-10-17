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
    /// Les dossiers à basculer, amorce comprise ; vide si l'amorce est déjà
    /// dans l'état visé.
    let folders: Set<String>

    /// Construit le plan. `chain` bas la bascule d'un seul dossier ; `chain`
    /// haut active récursivement les dépendances **requises** manquantes ou
    /// en pause, et met en pause récursivement les mods actifs qui exigent
    /// le dossier amorce.
    static func make(mod: ModItem, mods: [ModItem], chain: Bool) -> TogglePlan {
        make(mod: mod, index: Index(mods), chain: chain)
    }

    /// Même plan, sur un index déjà construit : un geste qui planifie
    /// plusieurs mods (`SavePausedReactivation`) ne le bâtit qu'une fois.
    static func make(mod: ModItem, index: Index, chain: Bool) -> TogglePlan {
        // Déjà premier niveau (mod seul ou en-tête de pack) → tel quel.
        // Sinon, résoudre le pack qui porte cet UniqueID — le même
        // rapprochement que la traversée des dépendances plus bas.
        let seedFolder: String = {
            if index.byFolder[mod.folderName] != nil {
                return mod.folderName
            }
            return index.topLevelFolder(for: mod.uniqueId) ?? mod.folderName
        }()

        // L'état visé est l'intention du clic : `mod` a été capturé par
        // valeur à l'empilement (voir `toggleMod`), tel que l'utilisateur
        // l'a vu. Quand l'appel s'exécute enfin, `mods` peut déjà refléter
        // une bascule antérieure — typiquement la chaîne d'un autre mod. Le
        // mod déjà dans l'état visé ne bouge plus. Inverser l'état *actuel*
        // (règle d'avant) défaisait cette bascule et réactivait toute la
        // chaîne de dépendances.
        let targetState = !mod.isEnabled
        let currentIsEnabled = index.byFolder[seedFolder]?.isEnabled ?? mod.isEnabled
        guard currentIsEnabled != targetState else {
            return TogglePlan(seedFolder: seedFolder, targetState: targetState, folders: [])
        }

        var folders: Set<String> = [seedFolder]
        if chain {
            if targetState {
                folders.formUnion(enableChain(from: seedFolder, index: index))
            } else {
                folders.formUnion(disableChain(from: seedFolder, index: index))
            }
        }
        return TogglePlan(seedFolder: seedFolder, targetState: targetState, folders: folders)
    }

    /// Les recherches du plan, faites une fois. Sans lui, chaque dépendance
    /// relisait tout le parc trois fois (dossier, dépendances, UniqueID) :
    /// ~250 ms par mod sur 1 039 mods, et 10 s de fil principal pour
    /// « Réactiver ces mods » d'une partie (`sample` du 2026-10-17). Premier
    /// trouvé dans l'ordre du parc, comme les parcours qu'il remplace.
    struct Index {
        let mods: [ModItem]
        let byFolder: [String: ModItem]
        /// UniqueID replié sans casse → dossier de premier niveau qui le
        /// porte : mod seul, ou en-tête de pack dont un enfant le déclare.
        private let topByUniqueId: [String: String]

        init(_ mods: [ModItem]) {
            self.mods = mods
            byFolder = Dictionary(mods.map { ($0.folderName, $0) }, uniquingKeysWith: { first, _ in first })
            var top: [String: String] = [:]
            for mod in mods {
                let ids = mod.isGroup ? (mod.children ?? []).map(\.uniqueId) : [mod.uniqueId]
                for id in ids where top[Self.key(id)] == nil { top[Self.key(id)] = mod.folderName }
            }
            topByUniqueId = top
        }

        /// Le repli de `caseInsensitiveCompare`, la comparaison d'avant.
        private static func key(_ uniqueId: String) -> String {
            uniqueId.folding(options: .caseInsensitive, locale: nil)
        }

        /// L'amorce d'un UniqueID ; `nil` si rien ne le porte.
        func topLevelFolder(for uniqueId: String) -> String? {
            topByUniqueId[Self.key(uniqueId)]
        }

        /// Toutes les dépendances d'un dossier de premier niveau (les enfants
        /// d'un pack s'additionnent).
        func dependencies(of folderName: String) -> [ModDependency] {
            guard let mod = byFolder[folderName] else { return [] }
            if mod.isGroup, let children = mod.children {
                return children.flatMap { $0.dependencies }
            }
            return mod.dependencies
        }
    }

    /// Activer : toutes les dépendances **requises** manquantes ou en pause,
    /// transitivement. La traversée continue à travers des dépendances déjà
    /// actives (`visited`, distinct de la liste à basculer) pour qu'un mod
    /// en pause deux niveaux plus bas d'une chaîne déjà active soit
    /// quand même rattrapé.
    private static func enableChain(from seedFolder: String, index: Index) -> Set<String> {
        var folders: Set<String> = []
        var queue = [seedFolder]
        var visited: Set<String> = [seedFolder]
        while !queue.isEmpty {
            let currentFolder = queue.removeFirst()
            let deps = index.dependencies(of: currentFolder)

            for dep in deps where dep.isRequired {
                if let depFolder = index.topLevelFolder(for: dep.uniqueId), !visited.contains(depFolder) {
                    visited.insert(depFolder)
                    let isDepFolderEnabled = index.byFolder[depFolder]?.isEnabled ?? false
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
    private static func disableChain(from seedFolder: String, index: Index) -> Set<String> {
        var folders: Set<String> = []
        var queue = [seedFolder]
        while !queue.isEmpty {
            let currentFolder = queue.removeFirst()

            var providedUniqueIds: [String] = []
            if let m = index.byFolder[currentFolder] {
                if m.isGroup, let children = m.children {
                    providedUniqueIds = children.map { $0.uniqueId }
                } else {
                    providedUniqueIds = [m.uniqueId]
                }
            }

            for otherMod in index.mods where otherMod.isEnabled && !folders.contains(otherMod.folderName) {
                let otherDeps = index.dependencies(of: otherMod.folderName)
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
