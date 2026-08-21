import Foundation
import Testing
@testable import StarHubTHCore

/// L'enveloppe XML qui soustrait les marques du jeu à la traduction. Le seul
/// contrat qui compte : `unwrap(wrap(s)) == s`, quoi que contienne `s`.
struct TokenShieldTests {

    @Test func aSourceWithoutAnyMarkerSurvivesTheRoundTrip() {
        let source = "Her roots grow very deep."
        #expect(TokenShield.unwrap(TokenShield.wrap(source)) == source)
    }

    @Test func theComposedFormsSurviveTheRoundTrip() {
        // Les trois formes que le lecteur de marques coupait en deux avant
        // d'être corrigé : elles méritent leur test ici aussi.
        for source in ["Bonjour $q 12 Yes#$b# et la suite",
                       "Ton enfant %kid1 et l'autre %kid2",
                       "#$action AddQuest 12#Fin"] {
            #expect(TokenShield.unwrap(TokenShield.wrap(source)) == source,
                    "aller-retour cassé sur \(source)")
        }
    }

    /// Le piège du XML : une source qui contient déjà `<`, `>` ou `&`.
    /// Sans échappement, elle casserait le document envoyé au service.
    @Test func angleBracketsAndAmpersandsSurviveTheRoundTrip() {
        let source = "5 < 6 & 7 > 3 <not a tag>"
        let wrapped = TokenShield.wrap(source)
        #expect(!wrapped.contains("<not a tag>"))
        #expect(TokenShield.unwrap(wrapped) == source)
    }

    /// CRLF : ce dépôt s'y est fait prendre deux fois. Une fin de ligne
    /// Windows est **un** Character en Swift.
    @Test func crlfSurvivesTheRoundTrip() {
        let source = "Première ligne\r\nDeuxième ligne"
        #expect(TokenShield.unwrap(TokenShield.wrap(source)) == source)
    }

    @Test func markersAreWrappedAndPlainTextIsNot() {
        let wrapped = TokenShield.wrap("Salut {{Name}} !")
        #expect(wrapped.contains("<x>{{Name}}</x>"))
        #expect(wrapped.hasPrefix("Salut "))
    }

    /// Le moteur rend les balises dans un autre ordre — le français déplace
    /// volontiers ce que l'anglais met en tête. Le déballage n'en souffre pas.
    @Test func reorderedTagsAreStillUnwrapped() {
        let translated = "<x>{{Name}}</x> arrive avec <x>%kid1</x>"
        #expect(TokenShield.unwrap(translated) == "{{Name}} arrive avec %kid1")
    }

    /// Une balise **perdue** par le moteur ne se répare pas ici : le déballage
    /// rend ce qu'il a reçu, et c'est le gate de marques qui refusera.
    @Test func aMissingMarkerIsNotPutBack() {
        #expect(TokenShield.unwrap("Bonjour !") == "Bonjour !")
    }

    /// Une balise que le moteur aurait laissée ouverte ne doit pas emporter la
    /// fin du texte : le déballage est tolérant, jamais destructeur.
    @Test func anUnclosedTagDoesNotSwallowTheRest() {
        #expect(TokenShield.unwrap("Bonjour <x>{{Name}} et voilà")
                == "Bonjour {{Name}} et voilà")
    }

    /// La requête part en XML : la réponse peut donc revenir avec n'importe
    /// quelle entité XML, pas seulement les trois que l'aller écrit. Une
    /// `&quot;` non déchiffrée atterrirait telle quelle dans un `fr.json` —
    /// une corruption visible, jamais signalée.
    @Test func everyXmlEntityInTheAnswerIsDecoded() {
        #expect(TokenShield.unwrap("Il a dit &quot;bonjour&quot;")
                == "Il a dit \"bonjour\"")
        #expect(TokenShield.unwrap("L&apos;été") == "L'été")
        #expect(TokenShield.unwrap("L&#39;été, &#x26; la suite") == "L'été, & la suite")
    }

    /// Le revers : une entité **écrite en toutes lettres** dans la source est
    /// du texte, pas une entité. Elle doit revenir intacte.
    @Test func anEntitySpelledOutInTheSourceIsNotDecoded() {
        for source in ["Le mot &quot; tel quel", "Et &#39; aussi", "Et &amp; enfin"] {
            #expect(TokenShield.unwrap(TokenShield.wrap(source)) == source,
                    "aller-retour cassé sur \(source)")
        }
    }
}
