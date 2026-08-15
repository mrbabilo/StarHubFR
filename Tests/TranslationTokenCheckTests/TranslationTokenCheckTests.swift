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
                == ["${him^her^them}$"])
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
        #expect(TranslationTokenCheck.isHard("${him^her^them}$"))
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
