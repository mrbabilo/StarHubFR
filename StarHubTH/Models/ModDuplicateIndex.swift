import Foundation

/// Les mods installés **plusieurs fois** — même `UniqueID`, plusieurs dossiers.
///
/// Un index, pas une recherche : `hasIssues` est appelé par le compteur du
/// cadrage **et** par le filtrage, sur chacune des lignes du parc. Regrouper
/// par identifiant à chaque appel serait quadratique sur 863 dossiers. Construit
/// une fois par scan, comme `installedUniqueIds`.
///
/// **Mesuré sur le parc le 2026-08-25 : 7 identifiants en double, sur 14
/// dossiers** — et trois d'entre eux ont **leurs deux copies actives** :
/// `FlyingTNT.Swim`, `FlyingTNT.SwimDiveMaps`, `FlyingTNT.SwimItems`, le mod
/// Swim installé à la fois à plat et dans son dossier de téléchargement. SMAPI
/// en charge une et ignore l'autre ; rien dans l'app ne le disait. Le relevé du
/// 2026-08-12 concluait « aucun actif des deux côtés » : ce n'est plus vrai.
public struct ModDuplicateIndex: Equatable, Sendable {
    /// `UniqueID` en minuscules → les dossiers qui le portent, **nommés**.
    ///
    /// Nommés et pas comptés : « installé 2 fois » est une devinette dans un
    /// parc de 863 dossiers. C'est « `Swim` et
    /// `Swim Mod-23169-1-9-0-1743804163/Swim` » qui dit lequel supprimer.
    public let folders: [String: [String]]
    /// Les mêmes → combien de ces dossiers sont **actifs**.
    public let activeCopies: [String: Int]

    public static let empty = ModDuplicateIndex(folders: [:], activeCopies: [:])

    public init(folders: [String: [String]], activeCopies: [String: Int]) {
        self.folders = folders
        self.activeCopies = activeCopies
    }

    /// Construit l'index depuis les mods installés, composants de packs compris.
    ///
    /// Un identifiant vide n'est **pas** un doublon : le parc en compte 111 —
    /// des manifestes qui n'en déclarent aucun et des en-têtes de pack, qui par
    /// nature n'en ont pas. Les compter ensemble ferait de chacun le doublon de
    /// tous les autres.
    public static func build(from entries: [(uniqueId: String, folderName: String,
                                            isEnabled: Bool)]) -> ModDuplicateIndex {
        var folders: [String: [String]] = [:]
        var active: [String: Int] = [:]
        for entry in entries {
            let key = entry.uniqueId.lowercased()
            guard !key.isEmpty else { continue }
            folders[key, default: []].append(entry.folderName)
            if entry.isEnabled { active[key, default: 0] += 1 }
        }
        return ModDuplicateIndex(folders: folders.filter { $0.value.count > 1 },
                                 activeCopies: active)
    }

    /// Ce qu'il faut signaler pour cet identifiant, `nil` s'il n'est installé
    /// qu'une fois.
    public func duplicate(of uniqueId: String) -> ModAnomaly.Duplicate? {
        let key = uniqueId.lowercased()
        guard let sharing = folders[key], sharing.count > 1 else { return nil }
        let named = sharing.sorted()
        // **Deux copies actives, c'est un défaut d'aujourd'hui** : SMAPI en
        // charge une et laisse l'autre de côté, et laquelle ne se devine pas.
        // Une seule active — ou aucune — n'est qu'un doublon dormant : rien ne
        // casse, mais le dossier occupe la place et se réactivera un jour.
        return (activeCopies[key] ?? 0) > 1 ? .active(folders: named) : .dormant(folders: named)
    }
}
