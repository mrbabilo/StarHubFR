import Foundation

/// P5-1 (audit UX 2026-10-16) — ce qu'activer un profil ferait au parc, sans
/// rien écrire. Avant, la seule façon de voir un profil était de l'activer :
/// environ 200 renommages sur le parc de l'auteur, puis un retour R5.
///
/// Tout part de `ProfileApplyPlan.moves`, le plan que le disque suivra : les
/// chiffres de l'aperçu sont ceux de l'activation, dossiers de tête compris
/// (un pack bouge en entier, les mods de SMAPI ne partent jamais en pause).
/// La garde de conflits de l'activation (`BulkConflictGateStore`) lit les
/// mêmes paires que l'aperçu annonce.
struct ProfileApplyPreview: Equatable {
    /// Triés par nom, pour qu'une liste de 200 se parcoure à l'œil.
    let toEnable: [ProfileApplyPlan.Move]
    let toDisable: [ProfileApplyPlan.Move]
    /// Les paires en conflit que l'activation rendrait actives (A5-T8).
    let conflicts: [ModConflictPair]

    var isEmpty: Bool { toEnable.isEmpty && toDisable.isEmpty }

    /// - Parameter mods: les mods de **tête** du dernier scan, comme pour
    ///   `ProfileApplyPlan.moves`.
    static func make(applying profile: ModProfile, to mods: [ModItem],
                     verdicts: ModConflictVerdicts, candidates: [ModConflictPair]) -> ProfileApplyPreview {
        let moves = ProfileApplyPlan.moves(applying: profile, to: mods)
        let enable = moves.filter { $0.direction == .enable }
        let disable = moves.filter { $0.direction == .disable }
        let byName: (ProfileApplyPlan.Move, ProfileApplyPlan.Move) -> Bool = {
            $0.modName.localizedStandardCompare($1.modName) == .orderedAscending
        }
        return ProfileApplyPreview(
            toEnable: enable.sorted(by: byName),
            toDisable: disable.sorted(by: byName),
            conflicts: mods.newConflicts(verdicts: verdicts, candidates: candidates,
                                         enabling: Set(enable.map(\.folderName)),
                                         disabling: Set(disable.map(\.folderName))))
    }
}
