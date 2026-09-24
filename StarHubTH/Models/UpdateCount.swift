import Foundation

/// Le compte que le badge « Mises à jour » affiche — barre latérale et
/// accueil — : le relevé SMAPI du **dernier lancement du jeu**, confronté au
/// disque, plus le résultat de la vérification Nexus.
///
/// **Pourquoi confronter.** Le relevé SMAPI date du lancement : un mod mis à
/// jour depuis y figure encore. Mesuré le 2026-09-24 sur le journal du jour :
/// 2 entrées « You can update », dont `Wildroot Chronicles 1.3.5` alors que
/// le disque portait `Cropgenics` en 1.4.1 — le badge comptait une mise à
/// jour déjà faite. Sans le parc sous la main, on ne juge rien : une entrée
/// non résolue reste comptée, au risque connu de gonfler le badge plutôt que
/// de l'écarter en silence.
///
/// `diskVersion` est une closure : le parc appartient au domaine Scan, et ce
/// type n'a pas à le connaître. L'appelant branche
/// `resolveModFolder(forLoggedName:)` — la même correspondance nom journal →
/// dossier que le reste de l'app (égalité exacte d'abord, repli tolérant).
public enum UpdateCount {

    /// Les mises à jour du relevé SMAPI que le disque ne couvre pas déjà —
    /// la liste affichée et le compte du badge en dérivent tous deux.
    public static func pendingEntries(outOfDate: [ModUpdateInfo],
                                      diskVersion: (String) -> String?)
    -> [ModUpdateInfo] {
        outOfDate.filter { update in
            guard let disk = diskVersion(update.name) else { return true }
            return !isAlreadyApplied(disk: disk, suggested: update.version)
        }
    }

    /// Les mises à jour à afficher : celles du relevé SMAPI que le disque ne
    /// couvre pas déjà, plus le compte Nexus passé tel quel.
    public static func pending(outOfDate: [ModUpdateInfo],
                               nexusCount: Int,
                               diskVersion: (String) -> String?) -> Int {
        pendingEntries(outOfDate: outOfDate, diskVersion: diskVersion).count + nexusCount
    }

    /// Le disque couvre-t-il déjà la version suggérée ?
    ///
    /// Seule une version **au moins égale** retire une entrée : comparer des
    /// préfixes numériques (« 1.4.1 » contre « 1.3.5 »), chaque segment
    /// manquant valant zéro. Une étiquette non numérique (« 1.6.1-unofficial »)
    /// coupe le préfixe sans l'invalider ; une version sans aucun chiffre ne
    /// se juge pas et l'entrée reste comptée. Préfixes égaux = déjà couvert :
    /// une version de disque qui prolonge la ligne suggérée (« 3.2.3 » contre
    /// « 3 ») ne mérite pas le badge.
    public static func isAlreadyApplied(disk: String, suggested: String) -> Bool {
        guard let a = numericPrefix(disk), let b = numericPrefix(suggested) else {
            return false
        }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return true
    }

    /// Les segments numériques de tête : « 1.6.1-unofficial » → [1, 6, 1] ;
    /// chaque segment porte ses **chiffres de tête** (« 1-unofficial-2 »
    /// vaut 1 — le tronquer faisait passer 1.6.1-unofficial pour 1.6, et
    /// couvrir 1.6.0) ; un segment sans chiffre arrête le préfixe, une
    /// version sans aucun segment numérique rend `nil`.
    private static func numericPrefix(_ version: String) -> [Int]? {
        var parts: [Int] = []
        for piece in version.split(separator: ".") {
            var digits = ""
            for ch in piece {
                guard ch.isNumber, ch.isASCII else { break }
                digits.append(ch)
            }
            guard let n = Int(digits) else { break }
            parts.append(n)
        }
        return parts.isEmpty ? nil : parts
    }
}
