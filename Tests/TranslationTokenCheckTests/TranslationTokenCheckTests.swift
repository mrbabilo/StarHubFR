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
        // spec C3-T9 §3 : une fin de page perdue avertit, ne bloque plus.
        #expect(found.first?.isHard == false)
    }

    @Test func whatBreaksTheGameBlocks() {
        for token in ["{{PlayerName}}", "{0}", "%item object 349 10 %%", "%fork", "%revealtaste",
                      "#$q", "#$action", "#$h", "#$1", "$q", "$b", "$e", "$k", "[128]", "[#]"] {
            #expect(TranslationTokenCheck.isHard(token), "\(token) doit bloquer")
        }
    }

    @Test func whatIsCosmeticWarns() {
        for token in ["$h", "$s", "$u", "$l", "$a", "$0", "$13", "@", "^", "#$b#", "#$b",
                      "#$e#", "#$k#", "%farm", "%kid1", "%spouse", "%noturn", "%"] {
            #expect(!TranslationTokenCheck.isHard(token), "\(token) doit avertir")
        }
    }

    /// `##` à la place de `#$b#` : un `#` nu ferme la conversation (relevé
    /// dans `Dialogue` : seul `#$b#` pose la continuation `{`).
    @Test func aBareHashReplacingAPageBreakBlocks() {
        let source = "Oui, Gabe...#$b#Mais ça va !$h"
        let target = "Oui, Gabe...##Mais ça va !$h"
        let hard = TranslationTokenCheck.mismatches(source: source, target: target).filter(\.isHard)
        #expect(hard.map(\.token) == [TranslationTokenCheck.bareHashToken])
    }

    /// `.$b#` sans son `#` d'ouverture : « $b » s'affiche et la page ferme.
    @Test func aBrokenPageBreakBlocks() {
        let source = "Bienvenue !$h#$b#Ma partie préférée.#$b#Ta journée ?"
        let target = "Bienvenue !$h#$b#Ma partie préférée.$b#Ta journée ?"
        let mismatches = TranslationTokenCheck.mismatches(source: source, target: target)
        // Bloquent : le `$b` affiché tel quel, et le `#` nu qui ferme la page.
        #expect(mismatches.filter(\.isHard).map(\.token) == ["$b", TranslationTokenCheck.bareHashToken])
        // La contrepartie, le `#$b#` perdu, n'avertit qu'à elle seule.
        #expect(mismatches.filter { !$0.isHard }
                == [.init(token: "#$b#", expected: 2, found: 1, isHard: false)])
    }

    /// `#$h` à la place de `$h` : une page qui ne contient qu'un portrait.
    @Test func aPortraitTurnedIntoAPageBlocks() {
        let mismatches = TranslationTokenCheck.mismatches(source: "Je t'aime aussi !$h",
                                                          target: "Je t'aime aussi !#$h")
        // Bloque : le `#$h` ajouté. Avertit : le portrait `$h` qu'il remplace.
        #expect(mismatches.filter(\.isHard) == [.init(token: "#$h", expected: 0, found: 1, isHard: true)])
        #expect(mismatches.filter { !$0.isHard } == [.init(token: "$h", expected: 1, found: 0, isHard: false)])
    }

    @Test func aDroppedPageBreakOnlyWarns() {
        let mismatches = TranslationTokenCheck.mismatches(source: "Salut.#$b#Ça va ?",
                                                          target: "Salut. Ça va ?")
        #expect(!mismatches.isEmpty)
        #expect(!mismatches.contains { $0.isHard })
    }

    @Test func aPlayerNameAddedInASelectorOnlyWarns() {
        let mismatches = TranslationTokenCheck.mismatches(source: "Merci, farmer !",
                                                          target: "Merci, ${Fermier^Fermière^@}$ !")
        #expect(!mismatches.contains { $0.isHard })
    }

    @Test func aLostPortraitOnlyWarns() {
        let mismatches = TranslationTokenCheck.mismatches(source: "Super !$h", target: "Super !")
        #expect(mismatches.map(\.token) == ["$h"])
        #expect(!mismatches.contains { $0.isHard })
    }

    /// Hors dialogue, un `#` est du texte : « Infini # » n'est pas une faute.
    @Test func aBareHashOutsideDialogueIsText() {
        #expect(TranslationTokenCheck.mismatches(source: "Unlimited", target: "Infini #").isEmpty)
    }

    /// Le `#` de `#$b#` devant un sélecteur n'est pas un `#` nu (Task 1).
    @Test func aSelectorAfterAPageBreakIsNotABareHash() {
        let mismatches = TranslationTokenCheck.mismatches(source: "Oui.#$b#Tu es là.",
                                                          target: "Oui.#$b#${Il^Elle}$ est là.")
        #expect(!mismatches.contains { $0.isHard })
    }

    @Test func narrationKeptIsNotAMismatch() {
        #expect(TranslationTokenCheck.mismatches(source: "%It's a bus.", target: "%C'est un bus.").isEmpty)
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
/// **1 092 des 4 331 lignes** signalées en écart de marques sur le parc
/// n'avaient que ce motif. Hors comparaison, donc : les bornes et le `^` qui
/// les sépare — rien d'autre. Le texte du sélecteur se traduit, mais les
/// marques qu'il porte restent comparées ; les exempter aussi aurait levé
/// 135 lignes de plus, toutes de vraies pertes.
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

    @Test func aMarkDroppedInsideASelectorIsStillCaught() {
        // La levée porte sur les **bornes** et leur `^`, rien de plus : le
        // nombre de sélecteurs ne se déduit pas de la source, mais un `$7`
        // perdu à l'intérieur casse le portrait comme il le ferait dehors.
        let found = TranslationTokenCheck.mismatches(
            source: "${He said $7hello^She said $7hello}$",
            target: "${Il a dit bonjour^Elle a dit bonjour}$")
        #expect(found.map(\.token) == ["$7"])
    }

    @Test func aSelectorLeftUnclosedInTheTargetIsCaught() {
        // Une borne fermante perdue ne fait plus un sélecteur : son `^` retombe
        // dans le texte comparé, et l'écart remonte. C'est ce qui reste de
        // filet une fois les sélecteurs bien formés mis hors comparaison.
        #expect(!TranslationTokenCheck.mismatches(source: "${a^b}$",
                                                  target: "${a^b").isEmpty)
    }
}
