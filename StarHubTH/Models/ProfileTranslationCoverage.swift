import Foundation

/// Ce qu'un mod du profil apporte, ou non, à la couverture française.
struct ProfileModTranslation: Identifiable, Equatable, Sendable {
    var id: String { uniqueId }
    let uniqueId: String
    /// Le nom affiché. Vient du mod installé — le profil ne sert de repli que
    /// pour les mods absents, qui ne sont pas comptés ici.
    let name: String
    /// Le dossier logique, seule clé qui ouvre la fiche du mod.
    let folderName: String
    /// Clés de la source (`default.json`), tous ses dossiers `i18n` propres.
    let total: Int
    /// Clés portant une traduction française non vide.
    let translated: Int

    var missingCount: Int { total - translated }

    /// Même règle d'arrondi que `TranslationCoverage.Coverage.displayPercent` :
    /// « 100 » seulement si tout est traduit, et un début de travail n'est
    /// jamais ramené à « 0 ».
    var displayPercent: Int {
        guard total > 0, translated > 0 else { return 0 }
        guard translated < total else { return 100 }
        return max(1, min(99, Int((Double(translated) / Double(total) * 100).rounded(.down))))
    }

    init(uniqueId: String, name: String, folderName: String,
         total: Int, translated: Int) {
        self.uniqueId = uniqueId
        self.name = name
        self.folderName = folderName
        self.total = total
        self.translated = translated
    }
}

/// L'état de la traduction française d'un profil entier.
struct ProfileTranslationSummary: Equatable, Sendable {
    /// Les mods du profil qui ont quelque chose à traduire — un `default.json`
    /// quelque part. Les autres (une retexture, un pack de cartes) ne comptent
    /// ni au numérateur ni au dénominateur : ils n'ont jamais eu de français à
    /// perdre.
    let translatableCount: Int
    /// Ceux dont chaque clé porte une traduction.
    let fullyTranslatedCount: Int
    let totalKeys: Int
    let translatedKeys: Int
    /// Les mods qu'il reste à traduire — partiels **et** intacts —, du plus
    /// gros reste au plus petit.
    let pending: [ProfileModTranslation]

    /// Rien de mesurable : le profil ne contient aucun mod traduisible.
    /// La pastille ne s'affiche pas dans ce cas ; annoncer « 0 % » ferait
    /// croire à un travail à faire qui n'existe pas.
    var isEmpty: Bool { translatableCount == 0 }

    var displayPercent: Int {
        guard totalKeys > 0, translatedKeys > 0 else { return 0 }
        guard translatedKeys < totalKeys else { return 100 }
        return max(1, min(99, Int((Double(translatedKeys) / Double(totalKeys) * 100).rounded(.down))))
    }

    init(translatableCount: Int, fullyTranslatedCount: Int,
         totalKeys: Int, translatedKeys: Int,
         pending: [ProfileModTranslation]) {
        self.translatableCount = translatableCount
        self.fullyTranslatedCount = fullyTranslatedCount
        self.totalKeys = totalKeys
        self.translatedKeys = translatedKeys
        self.pending = pending
    }
}

/// La couverture française d'un **profil** : ce que ses mods, pris ensemble,
/// affichent en français une fois le profil appliqué.
///
/// Ce n'est pas un défaut au sens des autres diagnostics — une clé sans
/// traduction s'affiche en anglais et le jeu tourne. C'est un **état** : le
/// profil « multi » et le profil « solo » n'ont pas la même liste de mods,
/// donc pas la même part de français en jeu, et rien ne le disait.
///
/// L'agrégation se fait sur les **clés**, pas sur les pourcentages par mod :
/// une moyenne de pourcentages donnerait le même poids à un mod de 9 clés et à
/// `East Scarp: NPCs`, qui en compte 11 021 — mesuré sur le parc.
enum ProfileTranslationCoverage {
    /// Le résumé d'un profil.
    ///
    /// - Parameters:
    ///   - profile: le profil à mesurer.
    ///   - installedMods: les mods installés, **packs dépliés** — un profil ne
    ///     retient que des composants.
    ///   - coverageByUniqueId: `UniqueID` **en minuscules** → couverture déjà
    ///     mesurée sur le disque. Un mod absent de cette table n'a rien à
    ///     traduire : `TranslationCoverage.coverage(forModAt:)` rend `nil`
    ///     quand aucun `default.json` n'existe, et l'appelant ne range que les
    ///     mesures réelles.
    ///
    /// Les mods que le profil réclame et qui **ne sont plus installés** sont
    /// écartés : on ne sait rien de leurs fichiers, et la section « mods
    /// manquants » les nomme déjà. Les compter à 0 % les ferait gronder deux
    /// fois et écraserait le pourcentage.
    static func summarize(profile: ModProfile,
                          installedMods: [ModItem],
                          coverageByUniqueId: [String: TranslationCoverage.Coverage])
        -> ProfileTranslationSummary {
        // La casse est ignorée partout où un `UniqueID` sert de clé : SMAPI
        // fait de même, et un manifeste réédité avec une majuscule différente
        // ferait autrement disparaître le mod du calcul.
        let byId = Dictionary(installedMods.map { ($0.uniqueId.lowercased(), $0) },
                              uniquingKeysWith: { first, _ in first })

        var translatable = 0, fullyTranslated = 0
        var totalKeys = 0, translatedKeys = 0
        var pending: [ProfileModTranslation] = []
        // Un profil peut nommer deux fois le même identifiant (import de
        // favoris, ajout manuel) : le compter deux fois doublerait ses clés.
        var seen = Set<String>()

        for uniqueId in profile.enabledModIds {
            let key = uniqueId.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            guard let mod = byId[key], let coverage = coverageByUniqueId[key] else { continue }
            guard coverage.total > 0 else { continue }

            translatable += 1
            totalKeys += coverage.total
            translatedKeys += coverage.translated

            if coverage.translated >= coverage.total {
                fullyTranslated += 1
            } else {
                pending.append(ProfileModTranslation(uniqueId: mod.uniqueId,
                                                     name: mod.name,
                                                     folderName: mod.folderName,
                                                     total: coverage.total,
                                                     translated: coverage.translated))
            }
        }

        // Le plus gros reste d'abord : c'est le mod dont la traduction change
        // le plus le pourcentage du profil. À égalité, l'ordre alphabétique,
        // pour que deux affichages successifs ne se réordonnent pas sous les
        // yeux de l'utilisateur.
        pending.sort {
            $0.missingCount != $1.missingCount
                ? $0.missingCount > $1.missingCount
                : $0.name.lowercased() < $1.name.lowercased()
        }

        return ProfileTranslationSummary(translatableCount: translatable,
                                         fullyTranslatedCount: fullyTranslated,
                                         totalKeys: totalKeys,
                                         translatedKeys: translatedKeys,
                                         pending: pending)
    }
}
