import Foundation

/// Un verdict smapi.io que la version installée a déjà réglé.
///
/// smapi.io juge un mod par son `UniqueID`, pas par sa version : il continue
/// de dire « cassé, prenez la version non officielle 1.1.3-unofficial.1 »
/// alors que c'est précisément elle qui est installée. Mesuré le 2026-09-25
/// sur le parc de l'auteur : **7 des 9 mods signalés** étaient déjà réglés —
/// 4 par la version (installée = recommandée, ou plus récente), 3 parce que
/// le mod de remplacement proposé (lien Nexus) est celui qui est installé,
/// sous le même `UniqueID`. Seuls restaient un mod en bêta sans remplaçant
/// et un mod cassé depuis 1.3.29.
///
/// Pur, sans SwiftUI — testé dans Core sur ces neuf cas.
public enum CompatibilityResolution {
    public enum Reason: Equatable, Sendable {
        /// La version installée est celle que smapi.io recommande, ou plus
        /// récente.
        case recommendedVersionInstalled(String)
        /// Le mod installé est la page Nexus que smapi.io propose en
        /// remplacement.
        case replacementInstalled(nexusId: String)
    }

    /// Pourquoi ce verdict ne demande plus rien pour ce mod installé, ou
    /// `nil` s'il reste valable.
    public static func resolution(of verdict: ModCompatibility,
                                  installedVersion: String,
                                  installedNexusId: String) -> Reason? {
        guard verdict.status.needsAttention else { return nil }
        let nexusId = installedNexusId.trimmingCharacters(in: .whitespaces)
        if !nexusId.isEmpty,
           verdict.links.contains(where: { nexusModId(inURL: $0.url) == nexusId }) {
            return .replacementInstalled(nexusId: nexusId)
        }
        if let recommended = recommendedVersion(in: verdict.summary),
           isAtLeast(installedVersion, recommended) {
            return .recommendedVersionInstalled(recommended)
        }
        return nil
    }

    /// La version entre parenthèses de la phrase smapi.io — « use unofficial
    /// version (1.1.3-unofficial.1-p1xel8ted) ». Seul format relevé sur le
    /// parc ; une phrase sans version entre parenthèses n'en donne aucune.
    static func recommendedVersion(in summary: String) -> String? {
        guard let open = summary.lastIndex(of: "("),
              let close = summary[open...].firstIndex(of: ")") else { return nil }
        let candidate = summary[summary.index(after: open)..<close]
            .trimmingCharacters(in: .whitespaces)
        guard let first = candidate.first, first.isNumber, !candidate.contains(" ") else { return nil }
        return candidate
    }

    static func nexusModId(inURL url: String) -> String? {
        guard let range = url.range(of: #"nexusmods\.com/stardewvalley/mods/(\d+)"#,
                                    options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(url[range].split(separator: "/").last ?? "")
    }

    /// `installed ≥ recommended`, à la manière de SemVer : numéros comparés
    /// un à un ; à numéros égaux, une version sans suffixe passe devant une
    /// préversion, et deux suffixes identiques sont égaux.
    static func isAtLeast(_ installed: String, _ recommended: String) -> Bool {
        let a = split(installed), b = split(recommended)
        for i in 0..<max(a.numbers.count, b.numbers.count) {
            let x = i < a.numbers.count ? a.numbers[i] : 0
            let y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x > y }
        }
        switch (a.suffix, b.suffix) {
        case (nil, _): return true
        case (_?, nil): return false
        case let (x?, y?): return x.lowercased() == y.lowercased()
        }
    }

    private static func split(_ version: String) -> (numbers: [Int], suffix: String?) {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "-", maxSplits: 1).map(String.init)
        let numbers = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        return (numbers, parts.count > 1 ? parts[1] : nil)
    }
}
