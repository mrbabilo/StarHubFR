import Testing
import Foundation
@testable import StarHubTHCore

/// Le lecteur de métadonnées .NET (**C4-T11 suite**) : ce que
/// `tools/gmcm_options.py` extrait avec dnfile, lu **en app** pour que les
/// mods nouvellement installés et les mises à jour soient couverts sans
/// attendre une release.
///
/// Variance du format **mesurée sur le parc** (455 DLL, 2026-09-15) avant
/// d'écrire une ligne — c'est elle qui borne le travail :
/// - **0** stream `#-` (non compressé) : le refuser est sans conséquence ;
/// - **26 DLL sur 455** portent des index de heap à 4 octets
///   (`heapSizes` 1 et 5) — les deux largeurs sont réellement exercées ;
/// - **aucune** table d'indirection (`FieldPtr`/`PropertyPtr`) non vide,
///   mais leur présence doit être *détectée*, pas ignorée : elles
///   casseraient le parcours par plage en silence ;
/// - plus grande table du parc : `MethodDef` = 21 844 lignes, donc tous
///   les index simples tiennent en 2 octets ici — le seuil des 4 octets
///   (65 536) reste implémenté et testé unitairement.
struct DotNetMetadataTests {

    // MARK: - Entiers compressés (§II.23.2)

    @Test func compressedIntegersDecodeTheirThreeWidths() {
        // Les trois formes de la spec, avec leurs bornes.
        func decode(_ bytes: [UInt8]) -> (value: Int, size: Int)? {
            var position = 0
            guard let value = DotNetMetadata.compressedUInt(bytes, &position) else { return nil }
            return (value, position)
        }
        #expect(decode([0x03])?.value == 0x03)          // 1 octet
        #expect(decode([0x7F])?.size == 1)
        #expect(decode([0x80, 0x80])?.value == 0x80)    // 2 octets
        #expect(decode([0xBF, 0xFF])?.value == 0x3FFF)
        #expect(decode([0xBF, 0xFF])?.size == 2)
        #expect(decode([0xC0, 0x00, 0x40, 0x00])?.value == 0x4000)  // 4 octets
        #expect(decode([0xDF, 0xFF, 0xFF, 0xFF])?.value == 0x1FFFFFFF)
        #expect(decode([0xDF, 0xFF, 0xFF, 0xFF])?.size == 4)
        // Tronqué : rien plutôt qu'une valeur inventée.
        #expect(decode([0x80]) == nil)
        #expect(decode([]) == nil)
    }

    // MARK: - Largeur des colonnes (§II.24.2.6)

    @Test func heapIndexWidthFollowsTheHeapSizesFlags() {
        // Mesuré : 429 DLL à 0 (tout en 2 octets), 17 à 1 (#Strings en 4),
        // 9 à 5 (#Strings et #Blob en 4).
        let small = DotNetMetadata.ColumnWidths(heapSizes: 0, rowCount: [:])
        #expect(small.string == 2)
        #expect(small.blob == 2)
        let wideStrings = DotNetMetadata.ColumnWidths(heapSizes: 1, rowCount: [:])
        #expect(wideStrings.string == 4)
        #expect(wideStrings.blob == 2)
        let wideBoth = DotNetMetadata.ColumnWidths(heapSizes: 5, rowCount: [:])
        #expect(wideBoth.string == 4)
        #expect(wideBoth.blob == 4)
    }

    @Test func simpleIndexWidthFollowsTheRowCount() {
        // Un index simple passe à 4 octets au-delà de 65 535 lignes. Le
        // parc n'y arrive pas (max 21 844), la règle existe quand même.
        let narrow = DotNetMetadata.ColumnWidths(heapSizes: 0, rowCount: [0x04: 65_535])
        #expect(narrow.simple(0x04) == 2)
        let wide = DotNetMetadata.ColumnWidths(heapSizes: 0, rowCount: [0x04: 65_536])
        #expect(wide.simple(0x04) == 4)
    }

    @Test func codedIndexWidthFollowsTheBiggestTargetTable() {
        // TypeDefOrRef : 2 bits de tag, donc bascule à 16 384 lignes.
        let narrow = DotNetMetadata.ColumnWidths(heapSizes: 0, rowCount: [0x02: 16_383])
        #expect(narrow.coded(.typeDefOrRef) == 2)
        let wide = DotNetMetadata.ColumnWidths(heapSizes: 0, rowCount: [0x02: 16_384])
        #expect(wide.coded(.typeDefOrRef) == 4)
    }

    // MARK: - Le fichier PE

    @Test func theMetadataRootIsFoundInARealAssembly() throws {
        let bytes = FixtureAssembly.bytes
        let offset = try #require(DotNetMetadata.metadataRootOffset(inPE: bytes))
        #expect(Array(bytes[offset..<(offset + 4)]) == Array("BSJB".utf8))
    }

    @Test func aFileThatIsNotAnAssemblyIsRefusedRatherThanGuessed() {
        #expect(DotNetMetadata.metadataRootOffset(inPE: []) == nil)
        #expect(DotNetMetadata.metadataRootOffset(inPE: Array("pas un PE du tout".utf8)) == nil)
        // Un en-tête MZ sans rien derrière : tronqué, pas exploitable.
        #expect(DotNetMetadata.metadataRootOffset(inPE: [0x4D, 0x5A] + [UInt8](repeating: 0, count: 200)) == nil)
    }

    // MARK: - Le contrat : les choix qu'un assembly déclare par ses types

    /// La réponse attendue est celle de l'oracle (`tools/gmcm_options.py`,
    /// dnfile) sur la même fixture — pas une liste écrite de mémoire.
    @Test func theFixtureYieldsExactlyItsEnumTypedProperties() throws {
        let options = try #require(DotNetAssemblyOptions.extract(assembly: FixtureAssembly.bytes))
        #expect(options == [
            "Placement": ["Strict", "Loose", "Anarchy"],
            "Enabled": ["None", "Sound", "Visuals", "All"],
            "Mode": ["Fast", "Slow"],
            "Fallback": ["Strict", "Loose", "Anarchy"],
        ])
    }

    /// Le piège que seul un assembly réel porte : `Outer.NestedMode` est
    /// le **dernier** TypeDef de la fixture. Sa plage de champs se termine
    /// au bout de la table, pas à la ligne suivante — une erreur d'un rang
    /// rendrait `Mode` vide ou tronqué.
    @Test func theLastTypeDefKeepsAllItsEnumValues() throws {
        let options = try #require(DotNetAssemblyOptions.extract(assembly: FixtureAssembly.bytes))
        #expect(options["Mode"] == ["Fast", "Slow"])
    }

    /// Même piège côté propriétés : `LastOwner` est la dernière entrée de
    /// `PropertyMap` et possède une propriété.
    @Test func theLastPropertyMapEntryIsNotDropped() throws {
        let options = try #require(DotNetAssemblyOptions.extract(assembly: FixtureAssembly.bytes))
        #expect(options["Fallback"] == ["Strict", "Loose", "Anarchy"])
    }

    /// Un enum d'un **autre** assembly (TypeRef) n'est pas un choix : c'est
    /// le cas `SButton`, que C4-T10 traite en contrôle de capture. La
    /// fixture porte `ModConfig.Hotkey: ExternalEnums.ExternalKey`.
    @Test func anEnumFromAnotherAssemblyIsNotAChoice() throws {
        let options = try #require(DotNetAssemblyOptions.extract(assembly: FixtureAssembly.bytes))
        #expect(options["Hotkey"] == nil)
    }

    /// Une classe à auto-propriétés porte des champs `<X>k__BackingField`
    /// qui ne sont **pas littéraux** : elle n'est pas un enum. Le premier
    /// passage de l'extracteur python s'y était fait prendre (89 champs
    /// faux, dont `FontSettings.GridLength`).
    @Test func aClassWithBackingFieldsIsNotMistakenForAnEnum() throws {
        let options = try #require(DotNetAssemblyOptions.extract(assembly: FixtureAssembly.bytes))
        #expect(options["Name"] == nil)
        #expect(options["Count"] == nil)
    }

    /// Le piège décisif : `Thresholds` est un **struct à constantes** —
    /// type valeur comme un enum, champs littéraux comme un enum, mais
    /// sans `value__`. Ce marqueur est le seul discriminant ; sans lui, un
    /// struct de constantes deviendrait une liste déroulante.
    @Test func aValueTypeWithConstantsButNoEnumMarkerIsNotAChoice() throws {
        let options = try #require(DotNetAssemblyOptions.extract(assembly: FixtureAssembly.bytes))
        #expect(options["Limits"] == nil)
    }

    /// Les types scalaires gardent leurs contrôles propres — un booléen
    /// n'est pas un menu à deux entrées (règle déjà mesurée en C4-T5).
    @Test func scalarPropertiesAreNotChoices() throws {
        let options = try #require(DotNetAssemblyOptions.extract(assembly: FixtureAssembly.bytes))
        #expect(options["Verbose"] == nil)
        #expect(options["Depth"] == nil)
        #expect(options["Scale"] == nil)
        #expect(options["Label"] == nil)
    }

    // MARK: - Les deux gardes que la fixture ne peut pas exercer
    //
    // Le sabotage de chacun laisse la suite verte : le premier est masqué
    // par le contrôle de bornes (le TypeRef de la fixture tombe hors de la
    // table TypeDef), le second parce que le dernier TypeDef de la fixture
    // a ses champs jusqu'au bout de la table Field. Ils se testent donc
    // sur leur **fonction**, avec l'entrée qui discrimine — la grammaire,
    // elle, est celle des octets réels relevés sur la fixture
    // (`Placement` = `28 00 11 10`, `Hotkey` = `28 00 11 41`).

    /// Le tag d'un `TypeDefOrRefOrSpecEncoded` : 0 = TypeDef (cet
    /// assembly), 1 = TypeRef (un autre). Même numéro de ligne, réponse
    /// opposée — sans ce tri, l'enum d'un autre assembly deviendrait un
    /// choix dès que son rang tombe dans la table locale.
    @Test func theSignatureTagTellsALocalTypeFromAForeignOne() throws {
        let bytes = FixtureAssembly.bytes
        let root = try #require(DotNetMetadata.metadataRootOffset(inPE: bytes))
        let file = try #require(DotNetAssemblyOptions.MetadataFile(bytes: bytes, root: root))
        // (ligne 4, tag 0) → `28 00 11 10`, exactement la signature que le
        // compilateur a émise pour `Placement`.
        #expect(file.internalValueTypeRow(inPropertySignature: [0x28, 0x00, 0x11, 0x10]) == 4)
        // (ligne 4, tag 1) → le même rang, mais dans l'autre assembly.
        #expect(file.internalValueTypeRow(inPropertySignature: [0x28, 0x00, 0x11, 0x11]) == nil)
        // ELEMENT_TYPE_CLASS (0x12) n'est pas un type valeur : une classe
        // n'a pas de valeurs à énumérer.
        #expect(file.internalValueTypeRow(inPropertySignature: [0x28, 0x00, 0x12, 0x10]) == nil)
        // Une ligne hors de la table locale ne se lit pas.
        #expect(file.internalValueTypeRow(inPropertySignature: [0x28, 0x00, 0x11, 0xFC]) == nil)
    }

    /// La plage d'une **dernière** ligne se termine au bout de la table
    /// visée. La lire sur la ligne suivante — qui n'existe pas — rendrait
    /// les octets de la table d'après, silencieusement.
    @Test func theLastRowsListEndsAtTheTargetTableEnd() throws {
        let bytes = FixtureAssembly.bytes
        let root = try #require(DotNetMetadata.metadataRootOffset(inPE: bytes))
        let file = try #require(DotNetAssemblyOptions.MetadataFile(bytes: bytes, root: root))
        let widths = file.widths
        let fieldListColumn = 4 + widths.string * 2 + widths.coded(.typeDefOrRef)
        let lastTypeDef = try #require(file.rowCount[0x02])
        let fieldCount = try #require(file.rowCount[0x04])
        #expect(file.listEnd(table: 0x02, row: lastTypeDef, column: fieldListColumn,
                             width: widths.simple(0x04), target: 0x04) == fieldCount + 1)
        // Une ligne quelconque, elle, s'arrête au début de la suivante.
        let firstStart = try #require(file.column(table: 0x02, row: 2, at: fieldListColumn,
                                                  width: widths.simple(0x04)))
        #expect(file.listEnd(table: 0x02, row: 1, column: fieldListColumn,
                             width: widths.simple(0x04), target: 0x04) == firstStart)
    }

    @Test func garbageIsRefusedWithoutCrashing() {
        #expect(DotNetAssemblyOptions.extract(assembly: []) == nil)
        #expect(DotNetAssemblyOptions.extract(assembly: [UInt8](repeating: 0x41, count: 5_000)) == nil)
        // Un assembly tronqué en plein milieu : refus, jamais un demi-résultat.
        let truncated = Array(FixtureAssembly.bytes.prefix(1_500))
        _ = DotNetAssemblyOptions.extract(assembly: truncated)  // ne doit pas planter
    }
}
