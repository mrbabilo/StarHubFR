import Testing
import Foundation
@testable import StarHubTHCore

/// Ces cas viennent de la spec et du parc réel, jamais du code de la référence
/// (GPL). La distinction dur/souple est ce qui a causé le plus de bugs chez
/// elle : un saut de ligne traité comme bloquant refuse une traduction correcte
/// qui a simplement replié ses lignes — l'allemand est plus long que l'anglais.
struct TranslationTokenCheckTests {

    @Test func extractionInheritsTheExistingVocabulary() {
        // Les formes composées, celles qu'une expression régulière naïve casse.
        #expect(TranslationTokenCheck.extract("Dis-lui ${him^her^them}$ bonjour")
                == ["${", "^", "^", "}$"])
        #expect(TranslationTokenCheck.extract("Reçois %item object 349 10 %% !")
                == ["%item object 349 10 %%"])
        #expect(TranslationTokenCheck.extract("{{Random:{{Range:1,5}}}} pommes")
                == ["{{Random:{{Range:1,5}}}}"])
        #expect(TranslationTokenCheck.extract("Salut@, ça va ?^Oui") == ["@", "^"])
    }

    @Test func aDroppedTokenAmongTwoIsCaught() {
        // Comparaison en multiensemble : perdre le second `#$b#` sur deux est
        // le cas qu'une comparaison d'ensembles laisse passer, et il casse un
        // dialogue en jeu.
        let found = TranslationTokenCheck.mismatches(source: "un#$b#deux#$b#trois",
                                                     target: "un#$b#deux trois")
        #expect(found.count == 1)
        #expect(found.first?.token == "#$b#")
        #expect(found.first?.expected == 2)
        #expect(found.first?.found == 1)
        #expect(found.first?.isHard == true)
    }

    @Test func theHardListMatchesWhatBreaksTheModAtRuntime() {
        #expect(TranslationTokenCheck.isHard("{{PlayerName}}"))
        #expect(TranslationTokenCheck.isHard("${"))
        #expect(TranslationTokenCheck.isHard("%item object 349 10 %%"))
        #expect(TranslationTokenCheck.isHard("#$b#"))
        #expect(TranslationTokenCheck.isHard("^"))
        #expect(TranslationTokenCheck.isHard("@"))
    }

    @Test func anIdenticalTargetHasNoMismatch() {
        #expect(TranslationTokenCheck.mismatches(source: "Salut {{Name}}#$b#",
                                                 target: "Salut {{Name}}#$b#").isEmpty)
    }

    @Test func anExtraTokenInTheTargetIsAlsoReported() {
        // Un token ajouté est aussi une divergence : il s'affichera tel quel en
        // jeu si le moteur ne sait pas le résoudre.
        let found = TranslationTokenCheck.mismatches(source: "Salut", target: "Salut {{Name}}")
        #expect(found.count == 1)
        #expect(found.first?.expected == 0)
        #expect(found.first?.found == 1)
    }

    @Test func plainProseYieldsNoToken() {
        // `l'été` ne doit pas être lu comme une marque : c'est la ponctuation
        // française la plus courante.
        #expect(TranslationTokenCheck.extract("l'été de l'ourse").isEmpty)
    }

    @Test func aReorderedTargetIsNotAMismatch() {
        // Le français déplace volontiers ce que l'anglais met en tête. Tant que
        // les marques y sont toutes, en même nombre, rien n'est cassé — bloquer
        // sur l'ordre refuserait des traductions justes.
        #expect(TranslationTokenCheck.mismatches(source: "{{A}} puis {{B}}",
                                                 target: "{{B}} d'abord, {{A}}").isEmpty)
    }
}

/// Le sélecteur de genre `${…}$` : le français en **ajoute** là où l'anglais
/// n'en a pas besoin, et c'est correct.
///
/// Mesuré sur le parc de l'auteur : 211 sélecteurs côté source, **1 528** côté
/// français. La localisation française du jeu fait exactement pareil —
/// `Jas/Sat8` passe d'un sélecteur à deux, `Abigail/summer_Tue4` d'un à trois,
/// parce que l'accord en genre porte en français sur des mots que l'anglais
/// laisse neutres.
///
/// Comparer ces marques au nombre revenait donc à refuser la traduction juste :
/// **1 227 des 4 331 lignes** signalées en écart de marques sur le parc
/// n'avaient que ce motif. Le contenu d'un sélecteur, bornes comprises, est
/// donc hors comparaison — il est du texte, et il se traduit.
struct TranslationTokenCheckGenderTests {

    @Test func aSelectorAddedByFrenchIsNotAMismatch() {
        // Le cas le plus fréquent du parc (`Always Raining in the Valley`) :
        // « farmer » est neutre, « fermier/fermière » ne l'est pas.
        #expect(TranslationTokenCheck.mismatches(source: "Hey farmer!",
                                                 target: "Hé ${fermier^fermiere}$ !").isEmpty)
    }

    @Test func aTranslatedSelectorIsNotAMismatch() {
        // Ce que fait la localisation du jeu, mot pour mot (`Pierre/Mon_inlaw_Abigail`).
        #expect(TranslationTokenCheck.mismatches(source: "${my son^daughter}$",
                                                 target: "${mon fils^ma fille}$").isEmpty)
    }

    @Test func oneSelectorBecomingThreeIsNotAMismatch() {
        // `Abigail/summer_Tue4` : un sélecteur en anglais, trois en français.
        #expect(TranslationTokenCheck.mismatches(
            source: "a ${guy^lady}$ moved in and got settled",
            target: "${un garçon^une fille}$ ${intéressant^intéressante}$ s'est ${installé^installée}$"
        ).isEmpty)
    }

    @Test func aLineBreakOutsideASelectorIsStillCompared() {
        // La contre-épreuve : le `^` d'un saut de ligne, lui, reste comparé.
        // Sans elle, la levée ci-dessus vaudrait pour tous les `^` du fichier.
        let found = TranslationTokenCheck.mismatches(source: "un^deux", target: "un deux")
        #expect(found.map(\.token) == ["^"])
    }

    @Test func aMarkDroppedOutsideASelectorIsStillCaught() {
        // Deuxième contre-épreuve : un `#$b#` perdu hors sélecteur reste dur,
        // même quand la ligne porte par ailleurs un sélecteur traduit.
        let found = TranslationTokenCheck.mismatches(
            source: "${my son^daughter}$ arrive#$b#et repart",
            target: "${mon fils^ma fille}$ arrive et repart")
        #expect(found.map(\.token) == ["#$b#"])
    }

    @Test func aSelectorLeftUnclosedInTheTargetIsCaught() {
        // Une borne fermante perdue ne fait plus un sélecteur : son `^` retombe
        // dans le texte comparé, et l'écart remonte. C'est ce qui reste de
        // filet une fois les sélecteurs bien formés mis hors comparaison.
        #expect(!TranslationTokenCheck.mismatches(source: "${a^b}$",
                                                  target: "${a^b").isEmpty)
    }
}
