import Foundation

/// Où en est un mod donné sur ce parc : absent, installé mais en pause, ou
/// actif — avec sa version. La carte « Sonde » de l'onglet Performances en
/// dérive : l'état de la sonde, et l'avertissement contre Profiler, qui fait
/// double emploi avec elle (D1 clos le 2026-10-03).
///
/// La comparaison plie la casse, comme SMAPI résout un `UniqueID`. Un
/// composant de pack compte comme un mod à part entière.
public enum ModPresence: Equatable, Sendable {
    case absent
    case paused(folderName: String, version: String)
    case enabled(folderName: String, version: String)

    /// La sonde StarHubFR (`companion/StarHubFR.Probe`).
    public static let probeId = "mrbabilo.StarHubFR.Probe"
    /// Profiler de SinZ (Nexus 12135) : la sonde reprend son code et
    /// mesure la même chose sans seuil ; les deux s'excluent.
    public static let profilerId = "SinZ.Profiler"

    public static func resolve(uniqueId: String, in mods: [ModItem]) -> ModPresence {
        let wanted = uniqueId.lowercased()
        for top in mods {
            for mod in top.components where mod.uniqueId.lowercased() == wanted {
                return mod.isEnabled
                    ? .enabled(folderName: mod.folderName, version: mod.version)
                    : .paused(folderName: mod.folderName, version: mod.version)
            }
        }
        return .absent
    }

    public var folderName: String? {
        switch self {
        case .absent: nil
        case .paused(let folder, _), .enabled(let folder, _): folder
        }
    }
}
