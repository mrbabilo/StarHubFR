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

/// Trois formes relevées dans la liste de `stardew-i18n-translator` et
/// confirmées dans le parc — toutes trois mal découpées auparavant.
struct TranslationTokenComposedFormsTests {
    private func codeParts(_ text: String) -> [String] {
        TranslationTokens.split(text).filter(\.isCode).map(\.text)
    }

    @Test func aGenderSelectorIsOneToken() {
        // 1520 occurrences dans le parc. Sans reconnaissance dédiée, le `^`
        // interne passait pour un saut de ligne et les mots pour du texte à
        // traduire — or traduire « him » en « lui » ici casse la sélection.
        #expect(codeParts("Dis-lui ${him^her^them}$ bonjour") == ["${him^her^them}$"])
    }

    @Test func aMailItemCommandIsOneToken() {
        // `%item object 349 10 351 10 %%` : les nombres sont des identifiants
        // d'objet, pas du texte. En marquer seulement `%item` laissait le reste
        // à la merci du traducteur.
        #expect(codeParts("Cadeau %item object 349 10 %% pour toi")
                == ["%item object 349 10 %%"])
    }

    @Test func aMailActionCommandIsOneToken() {
        #expect(codeParts("%action AddQuest Mod.Quest %%") == ["%action AddQuest Mod.Quest %%"])
    }

    @Test func aBareSubstitutionStillWorks() {
        // `%farm` sans `%%` reste une substitution simple.
        #expect(codeParts("Bienvenue à %farm !") == ["%farm"])
    }

    @Test func composedFormsPreserveTheText() {
        let source = "Salut ${him^her}$, prends %item object 349 %% et @^à bientôt"
        let segments = TranslationTokens.split(source)
        #expect(segments.map(\.text).joined() == source)
        #expect(segments.filter(\.isCode).map(\.text)
                == ["${him^her}$", "%item object 349 %%", "@", "^"])
    }

    // MARK: bornes mesurées sur le parc (2026-08-15)

    @Test func aTwoDigitPortraitCommandIsNotCutInHalf() {
        // `$10` était rendu `$1`, laissant le `0` au texte traduisible : un
        // traducteur pouvait le supprimer sans que rien ne le signale.
        #expect(codeParts("Portrait $10 puis $2") == ["$10", "$2"])
        #expect(codeParts("Expression $h et $s") == ["$h", "$s"])
    }

    @Test func aNumberedSubstitutionKeepsItsNumber() {
        // `%kid1` et `%kid2` se réduisaient tous deux à `%kid` : intervertir le
        // premier et le second enfant passait inaperçu à la comparaison.
        #expect(codeParts("Enfants %kid1 et %kid2") == ["%kid1", "%kid2"])
        #expect(codeParts("Bienvenue à %farm !") == ["%farm"])
    }

    @Test func onlyAttestedMultiLetterCommandsAreTakenWhole() {
        // Mesuré sur le parc : après `#$`, 22 formes multi-lettres existent et
        // **une seule** est une commande — `#$action`, 812 fois. Les 21 autres
        // sont une commande d'une lettre suivie de prose : `#$bWhat` (19 fois)
        // est `#$b` puis « What ». Tout avaler soustrairait ce texte à la
        // traduction.
        #expect(codeParts("Pause#$bWhat a day") == ["#$b"])
        #expect(codeParts("Sep #$action AddQuest") == ["#$action"])
    }

    @Test func aClosingHashIsNotStolenFromTheNextSeparator() {
        // `#$action#$b#` : le `#` qui suit `action` est la tête du séparateur
        // suivant, pas la fermeture du premier. L'avaler dégradait `#$b#` en
        // `$b` et laissait un `#` orphelin.
        #expect(codeParts("Texte#$action#$b#suite") == ["#$action", "#$b#"])
        #expect(codeParts("Pause#$b#suite") == ["#$b#"], "la fermeture normale tient")
    }

    @Test func aHashPrefixedCommandKeepsItsHashAndItsWord() {
        // `#$action AddQuest` se réduisait à `$a`, abandonnant « ction
        // AddQuest » à la traduction. Le `#` de tête se perdait aussi sur les
        // formes non refermées.
        #expect(codeParts("Sep #$r et #$action AddQuest") == ["#$r", "#$action"])
        #expect(codeParts("Pause#$b#suite") == ["#$b#"], "la forme refermée ne change pas")
    }

    @Test func theTextStaysIntactAroundTheseForms() {
        // Le découpage doit rester réversible : c'est ce qui garantit qu'aucun
        // caractère ne se perd à l'affichage.
        let source = "Portrait $10, %kid1 et #$action AddQuest"
        let segments = TranslationTokens.split(source)
        #expect(segments.map(\.text).joined() == source)
    }
}
