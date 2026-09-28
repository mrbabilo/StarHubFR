import Foundation

/// Paires de mods incompatibles connues d'avance, tenues à la main. Jugées sur
/// l'`UniqueID` (le nom de dossier change d'un parc à l'autre, l'identifiant
/// du manifeste non ; sans la casse, comme SMAPI), rendues en paires de
/// dossiers logiques pour rejoindre les paires déclarées et observées
/// (`ModConflictVerdicts.candidates`) : même alerte quand les deux sont
/// actifs, même avertissement à l'activation, même écartement possible.
public enum KnownIncompatibilities {
    /// La sonde StarHubFR et Profiler (SinZ) posent les mêmes minuteurs
    /// (postfix sur `DebugTimings`, écoute des pauses GC) : actifs ensemble,
    /// chacun ajoute son coût à ce que l'autre mesure. Aucun plantage mesuré ;
    /// déclarée incompatible par l'auteur le 2026-09-29.
    static let rules: [(first: String, second: String, reasonKey: String)] = [
        ("mrbabilo.StarHubFR.Probe", "SinZ.Profiler", "conflicts_known_probe_profiler"),
    ]

    /// Les paires présentes dans le parc (composants de pack compris).
    public static func pairs(in mods: [ModItem]) -> [ModConflictPair] {
        resolved(in: mods).map(\.pair)
    }

    /// La clé L10n qui dit pourquoi la paire est incompatible ; `nil` pour
    /// une paire qui n'est pas connue d'avance.
    public static func reasonKey(for pair: ModConflictPair, in mods: [ModItem]) -> String? {
        resolved(in: mods).first { $0.pair == pair }?.reasonKey
    }

    private static func resolved(in mods: [ModItem]) -> [(pair: ModConflictPair, reasonKey: String)] {
        let flat = mods.flattenedMods
        func folders(_ uniqueId: String) -> [String] {
            flat.filter { $0.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame }.map(\.folderName)
        }
        return rules.flatMap { rule in
            folders(rule.first).flatMap { first in
                folders(rule.second).map { (ModConflictPair(first, $0), rule.reasonKey) }
            }
        }
    }
}
