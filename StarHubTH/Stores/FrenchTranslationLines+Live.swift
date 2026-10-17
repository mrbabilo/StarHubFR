import Foundation

/// Une ligne de la page Traductions FR : le mod candidat, son `ModItem`
/// vivant pour agir, et son statut dérivé du cache.
struct FrenchTranslationLine: Identifiable {
    let candidate: FrenchTranslationSweep.Candidate
    let mod: ModItem
    let status: FrenchTranslationSweep.Status
    var id: String { candidate.id }
}

/// La page et le badge de la barre (P5-10) lisent les mêmes lignes : deux
/// calculs finiraient par compter autrement. Hors du fichier du ViewModel
/// (règle F1-T2).
extension StarHubTHViewModel {
    var frenchTranslationLines: [FrenchTranslationLine] {
        let store = translationSweep
        let byFolder = Dictionary(mods.map { ($0.folderName, $0) }, uniquingKeysWith: { first, _ in first })
        return FrenchTranslationSweep.candidates(
            among: mods,
            hasInstalledTranslation: { self.tracksTranslation(for: $0) },
            nexusModId: { Int(self.resolvedNexusModId(for: $0)) })
        .compactMap { candidate in
            guard let mod = byFolder[candidate.folderName] else { return nil }
            return FrenchTranslationLine(
                candidate: candidate, mod: mod,
                status: FrenchTranslationSweep.status(
                    entry: store.entry(for: candidate.folderName),
                    installed: translation(for: mod) ?? declaredTracked(for: mod)))
        }
    }

    /// Le badge « Traductions FR » : les mods actifs qui appellent un geste
    /// (`FrenchTranslationSweep.callsForAction`), lus sur le cache.
    var frenchTranslationBadgeCount: Int {
        let store = translationSweep
        return frenchTranslationLines.filter {
            FrenchTranslationSweep.callsForAction($0.status, candidate: $0.candidate,
                                                  entry: store.entry(for: $0.candidate.folderName))
        }.count
    }
}
