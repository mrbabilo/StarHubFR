import Testing
import Foundation
@testable import StarHubTHCore

/// Ce qui, dans une valeur de traduction, n'est **pas** du texte à traduire.
///
/// Un fichier i18n de Stardew Valley mêle la phrase et des marques que le jeu
/// interprète : un token Content Patcher, un séparateur de dialogue, la
/// commande qui change l'expression du portrait. Les traduire ou les déplacer
/// casse le mod — au mieux le texte s'affiche mal, au pire le dialogue ne se
/// déclenche plus.
///
/// Relevé sur les 473 fichiers français du parc : 118 000 commandes de portrait,
/// 72 000 séparateurs `#$…#`, 16 000 `@`, 13 000 `^`, 3 600 tokens Content
/// Patcher, 2 200 substitutions `%…`.
struct TranslationTokenTests {
    private func segments(_ text: String) -> [TranslationTokens.Segment] {
        TranslationTokens.split(text)
    }

    private func codeParts(_ text: String) -> [String] {
        segments(text).filter(\.isCode).map(\.text)
    }

    @Test func plainTextHasNoCode() {
        let parts = segments("Bonjour, comment allez-vous ?")
        #expect(parts.count == 1)
        #expect(parts.first?.isCode == false)
    }

    @Test func findsAContentPatcherToken() {
        // Vu tel quel : « le brouillon d'Elliott pour {{book}} ».
        #expect(codeParts("le brouillon pour {{book}}.") == ["{{book}}"])
    }

    @Test func aNestedContentPatcherTokenIsOneUnit() {
        // `{{Random:{{Range:1,5}}}}` est une forme réelle. Une expression
        // régulière plate refermerait le token au premier `}}` et couperait en
        // deux ce qui n'en fait qu'un.
        #expect(codeParts("valeur {{Random:{{Range:1,5}}}} ici") == ["{{Random:{{Range:1,5}}}}"])
    }

    @Test func findsAPositionalPlaceholder() {
        #expect(codeParts("Il reste {0} jours") == ["{0}"])
    }

    @Test func findsADialogueSeparator() {
        // `#$b#` marque une pause, `#$e#` une fin de page.
        #expect(codeParts("Bonjour#$b#Au revoir") == ["#$b#"])
    }

    @Test func findsAPortraitCommand() {
        // Les commandes d'expression sont numériques (`$2`, `$9`) autant que
        // littérales (`$h`) — ne reconnaître que les lettres en manquerait la
        // majorité.
        #expect(codeParts("Qu'est-ce que...$2 rien.") == ["$2"])
        #expect(codeParts("Salut$h !") == ["$h"])
    }

    @Test func aSeparatorIsNotCutIntoPieces() {
        // `#$b#` contient `$b` : le reconnaître d'abord en tant que séparateur
        // évite de rendre trois fragments là où il n'y a qu'une marque.
        let parts = codeParts("un$2#$b#deux")
        #expect(parts == ["$2", "#$b#"])
    }

    @Test func findsASubstitution() {
        #expect(codeParts("Voici %item pour vous") == ["%item"])
    }

    @Test func findsAnItemIndex() {
        #expect(codeParts("Apporte [#] à Robin") == ["[#]"])
    }

    @Test func findsPlayerNameAndLineBreak() {
        let parts = codeParts("Salut @^ça va ?")
        #expect(parts == ["@", "^"])
    }

    @Test func textAroundTokensIsPreserved() {
        // Le découpage doit rendre le texte d'origine à l'identique : c'est ce
        // qui garantit qu'aucun caractère n'est perdu à l'affichage.
        let source = "Bonjour @, il reste {0} jours#$b#à bientôt !"
        #expect(segments(source).map(\.text).joined() == source)
    }

    @Test func anUnclosedTokenIsNotCode() {
        // Un `{{` jamais refermé est du texte abîmé, pas une marque : le
        // signaler comme du code laisserait croire qu'il ne faut pas y toucher.
        #expect(codeParts("texte {{jamais fermé").isEmpty)
    }

    @Test func aLoneBraceIsNotAToken() {
        #expect(codeParts("accolade { seule").isEmpty)
    }

    @Test func realDialogueIsSplitCorrectly() {
        // Cas réel ([CP] Miihaus Abigail Event Ex).
        let source = "La mine...$9#$b#Hm, c'est mystérieux.$3"
        #expect(codeParts(source) == ["$9", "#$b#", "$3"])
        #expect(segments(source).map(\.text).joined() == source)
    }
}
