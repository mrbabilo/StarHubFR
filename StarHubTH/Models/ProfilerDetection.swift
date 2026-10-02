import Foundation

/// D1-T1 — où en est **Profiler** (SinZ) sur ce parc : absent, installé mais
/// en pause, ou actif. Le guidage de l'onglet Performances en dérive —
/// installer, activer, jouer une session représentative, revenir.
///
/// L'identifiant vient du dump Pathoschild (`SinZ.Profiler`, Nexus 12135) ;
/// la comparaison plie la casse, comme SMAPI résout un `UniqueID`. Un
/// composant de pack compte comme un mod à part entière.
public enum ProfilerDetection: Equatable, Sendable {
    case absent
    case paused(folderName: String)
    case enabled(folderName: String)

    static let uniqueId = "sinz.profiler"

    public static func resolve(mods: [ModItem]) -> ProfilerDetection {
        for top in mods {
            for mod in top.components where mod.uniqueId.lowercased() == uniqueId {
                return mod.isEnabled
                    ? .enabled(folderName: mod.folderName)
                    : .paused(folderName: mod.folderName)
            }
        }
        return .absent
    }
}
