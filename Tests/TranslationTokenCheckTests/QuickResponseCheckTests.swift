import Testing
import Foundation
@testable import StarHubTHCore

/// `$y 'question_réponse_réplique…'` tel que le jeu le lit
/// (`Dialogue.parseDialogueString`, relu dans Stardew Valley.dll le
/// 2026-10-14) : texte après la **première** apostrophe, dernier caractère
/// retiré, découpe sur `_`. Une apostrophe française ou un `_` perdu change
/// les réponses — un nombre impair de `_` fait planter le dialogue.
struct QuickResponseCheckTests {
    /// Cas réel du parc : Sterling, `winter_Mon6` (Always Raining in the
    /// Valley). Source sans apostrophes ; le « j'aie » français devient le
    /// début de la réponse rapide, et ses deux réponses disparaissent en jeu.
    @Test func aFrenchApostropheInAnUnquotedQuickResponseIsCaught() {
        let source = "$y Now tell me, @. Are your parents bakers?_Yes, actually!_No wonder you're a cutie pie then!_Afraid not._Really? Because you're the biggest cutie pie I've ever seen.$10"
        let target = "$y Dis-moi, @. Tes parents sont-ils des boulangers ?_Oui, en fait !_Pas étonnant que tu sois un petit chou alors !_Non, malheureusement._Vraiment ? Parce que tu es le plus grand petit chou que j'aie jamais vu.$10"
        let found = TranslationTokenCheck.mismatches(source: source, target: target)
            .filter { $0.token == TranslationTokenCheck.quickResponseToken }
        #expect(found == [.init(token: TranslationTokenCheck.quickResponseToken, expected: 4, found: 0, isHard: true)])
        // L'apostrophe typographique ne coupe rien : c'est la correction.
        let fixed = target.replacingOccurrences(of: "j'aie", with: "j’aie")
        #expect(TranslationTokenCheck.mismatches(source: source, target: fixed).isEmpty)
    }

    /// Entre apostrophes, celles du texte ne gênent pas : le jeu ne regarde
    /// que la première, et retire la dernière.
    @Test func apostrophesInsideAQuotedQuickResponseAreHarmless() {
        let source = "Hey!#$y 'Do you like summer?_Yes_Me too!_No_Shame.'"
        let target = "Salut !#$y 'Tu aimes l'été ?_Oui_Moi aussi !_Non_Dommage, c'est la saison.'"
        #expect(TranslationTokenCheck.mismatches(source: source, target: target).isEmpty)
    }

    @Test func aLostOrAddedSeparatorIsCaught() {
        let source = "$y 'Ready?_Yes_Great._No_Later.'"
        let lost = TranslationTokenCheck.mismatches(source: source, target: "$y 'Prêt ?_Oui_Super. Non_Plus tard.'")
        #expect(lost.contains { $0.token == TranslationTokenCheck.quickResponseToken && $0.found == 3 && $0.expected == 4 })
        let added = TranslationTokenCheck.mismatches(source: source, target: "$y 'Prêt ?_Oui_Super_Non_Plus_tard.'")
        #expect(added.contains { $0.token == TranslationTokenCheck.quickResponseToken && $0.found == 5 })
    }

    /// Le jeu ne lit `$y` qu'en tête d'un segment entre `#` : ailleurs, ce
    /// n'est pas une réponse rapide, ses `_` sont du texte.
    @Test func onlyASegmentStartingWithTheCommandCounts() {
        #expect(TranslationTokenCheck.quickResponseSeparators("Hello $y 'a_b_c'") == [])
        #expect(TranslationTokenCheck.quickResponseSeparators("Hi#$y 'a_b_c'#$e#$y 'd_e_f_g_h'") == [2, 4])
        #expect(TranslationTokenCheck.quickResponseSeparators("$yes 'a_b_c'") == [])
    }
}
