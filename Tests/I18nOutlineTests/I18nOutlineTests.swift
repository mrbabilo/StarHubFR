import Testing
import Foundation
@testable import StarHubTHCore

/// La structure qu'un auteur donne à son fichier de traduction.
///
/// Les auteurs séparent leurs clés par des commentaires — « Config »,
/// « Dialogue locationnel », « Titres des nouveaux livres d'Elliott ». C'est la
/// seule structure fiable de ces fichiers : déduire un personnage des clés ne
/// marche pas (le nom désigne souvent un lieu ou un participant d'événement).
///
/// 167 des 450 fichiers français du parc en portent, 3290 sections au total.
///
/// L'ordre des clés sort du même parcours. Il ne sert pas au regroupement, mais
/// il sera **indispensable à l'écriture** : réordonner un fichier rend son diff
/// illisible, et `JSONSerialization` ne préserve pas l'ordre.
struct I18nOutlineTests {
    @Test func keysComeBackInFileOrder() {
        let text = """
        {
          "zebre": "1",
          "alpha": "2"
        }
        """
        // Surtout pas triées : c'est l'ordre du fichier qu'il faut restituer.
        #expect(I18nOutline.read(text).orderedKeys == ["zebre", "alpha"])
    }

    @Test func aCommentBecomesTheSectionOfTheKeysBelow() {
        let text = """
        {
          // Config
          "a": "1",
          "b": "2"
        }
        """
        let outline = I18nOutline.read(text)
        #expect(outline.section(of: "a") == "Config")
        #expect(outline.section(of: "b") == "Config")
    }

    @Test func aNewCommentOpensANewSection() {
        let text = """
        {
          // Config
          "a": "1",
          // Dialogue
          "b": "2"
        }
        """
        let outline = I18nOutline.read(text)
        #expect(outline.section(of: "a") == "Config")
        #expect(outline.section(of: "b") == "Dialogue")
    }

    @Test func keysBeforeAnyCommentHaveNoSection() {
        let text = """
        {
          "a": "1",
          // Config
          "b": "2"
        }
        """
        let outline = I18nOutline.read(text)
        #expect(outline.section(of: "a") == nil)
        #expect(outline.section(of: "b") == "Config")
    }

    @Test func decorationLinesAreNotSections() {
        // Forme réelle ([CP] Large Quail Mayo) : une ligne de tirets encadre le
        // vrai titre. La retenir donnerait des sections nommées « ------ ».
        let text = """
        {
          // --------------------------------------
          // Config
          // --------------------------------------
          "a": "1"
        }
        """
        #expect(I18nOutline.read(text).section(of: "a") == "Config")
    }

    @Test func aDoubleSlashInsideAValueIsNotASection() {
        // Une URL dans une valeur ne doit pas ouvrir une section.
        let text = """
        {
          // Vraie section
          "a": "https://nexusmods.com/x"
        }
        """
        #expect(I18nOutline.read(text).section(of: "a") == "Vraie section")
    }

    @Test func aDoubleSlashInsideAKeyIsNotASection() {
        let text = #"{"a//b": "1"}"#
        let outline = I18nOutline.read(text)
        #expect(outline.orderedKeys == ["a//b"])
        #expect(outline.section(of: "a//b") == nil)
    }

    @Test func blockCommentsAlsoTitleASection() {
        let text = """
        {
          /* Config */
          "a": "1"
        }
        """
        #expect(I18nOutline.read(text).section(of: "a") == "Config")
    }

    @Test func aFileWithoutCommentsHasNoSections() {
        let outline = I18nOutline.read(#"{"a": "1", "b": "2"}"#)
        #expect(outline.orderedKeys == ["a", "b"])
        #expect(outline.hasSections == false)
    }

    @Test func nestedKeysAreNotCollected() {
        // Un fichier i18n est plat, mais un objet imbriqué ne doit pas polluer
        // la liste des clés avec les siennes.
        let text = """
        {
          "a": {"interne": "1"},
          "b": "2"
        }
        """
        #expect(I18nOutline.read(text).orderedKeys == ["a", "b"])
    }

    @Test func schemaIsNotAKey() {
        // Même convention que le parseur : `$schema` est une annotation
        // d'éditeur, pas une entrée de traduction.
        #expect(I18nOutline.read(#"{"$schema": "http://x", "a": "1"}"#).orderedKeys == ["a"])
    }

    @Test func aRealFileShape() {
        // Forme relevée sur `.Automate`.
        let text = """
        {
          // main options
          "config.Enabled.name": "Activé",
          "config.Enabled.desc": "Si Automate est actif.",

          // connectors
          "config.Connectors.name": "Connecteurs"
        }
        """
        let outline = I18nOutline.read(text)
        #expect(outline.orderedKeys.count == 3)
        #expect(outline.section(of: "config.Enabled.desc") == "main options")
        #expect(outline.section(of: "config.Connectors.name") == "connectors")
    }
}

/// Le piège des fins de ligne, déjà payé une fois dans `I18nLenientParser`.
struct I18nOutlineLineEndingTests {
    @Test func aCrlfFileKeepsItsKeys() {
        // En Swift, `\r\n` est **un seul** Character, égal ni à `"\n"` ni à
        // `"\r"`. Comparer littéralement faisait courir la coupure du
        // commentaire jusqu'à la fin du fichier : un fichier CRLF perdait
        // toutes ses clés. Forme réelle (`.Automate`), 1471 fichiers du parc
        // sont en CRLF.
        let text = "{\r\n  /*****\r\n  ** Titre\r\n  *****/\r\n  // main options\r\n  \"a\": \"1\"\r\n}"
        let outline = I18nOutline.read(text)
        #expect(outline.orderedKeys == ["a"])
        #expect(outline.section(of: "a") == "main options")
    }

    @Test func aLoneCarriageReturnEndsACommentToo() {
        let outline = I18nOutline.read("{\r  // section\r  \"a\": \"1\"\r}")
        #expect(outline.orderedKeys == ["a"])
        #expect(outline.section(of: "a") == "section")
    }
}

/// Les clés non quotées, que trois mods du parc emploient.
struct I18nOutlineBareKeyTests {
    @Test func aBareKeyIsCollectedLikeAnyOther() {
        // `WearMoreRings`, `BiggerBackpack` et `MovementSpeed` écrivent leurs
        // clés sans guillemets. Le parseur les répare ; l'analyse doit voir les
        // mêmes clés que lui, sans quoi l'ordre qu'elle rend est incomplet —
        // et c'est cet ordre qui guidera l'écriture.
        let text = """
        {
          // Config
          RingsName: "Anneaux",
          "quoted": "1"
        }
        """
        let outline = I18nOutline.read(text)
        #expect(outline.orderedKeys == ["RingsName", "quoted"])
        #expect(outline.section(of: "RingsName") == "Config")
    }

    @Test func aBareWordThatIsNotAKeyIsIgnored() {
        // `true` est une valeur, pas une clé : rien ne la suit d'un `:`.
        let outline = I18nOutline.read(#"{"a": true, "b": "1"}"#)
        #expect(outline.orderedKeys == ["a", "b"])
    }
}
