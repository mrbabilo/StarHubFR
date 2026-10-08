import Foundation

/// Les choix qu'un mod C# déclare **par ses types**, lus dans sa DLL
/// (**C4-T11 suite**). Une propriété dont le type est un enum **de
/// l'assembly lui-même** est un réglage à valeurs figées : c'est ce que
/// MCM voit en jeu, parce que les mods le déclarent à son API — ici, la
/// même information se lit hors jeu dans les métadonnées, sans décoder le
/// moindre corps de méthode.
///
/// Trois refus délibérés, chacun mesuré sur le parc (455 DLL) :
/// - un enum d'un **autre** assembly (TypeRef) n'est pas un choix — c'est
///   le cas `SButton`, que le contrôle de capture traite (C4-T10) ;
/// - un stream de tables **non compressé** (`#-`) n'est pas lu : absent du
///   parc, et son schéma diffère ;
/// - une table d'**indirection** non vide (`FieldPtr`, `PropertyPtr`) fait
///   abandonner : elle casse le parcours par plage, et rendre une réponse
///   fausse en silence serait pire que ne rien rendre. Aucune sur le parc.
public enum DotNetAssemblyOptions {

    /// Nom de propriété → valeurs de l'enum, pour tout l'assembly.
    /// `nil` quand le fichier n'est pas un assembly CLI exploitable.
    public static func extract(assembly bytes: [UInt8]) -> [String: [String]]? {
        guard let root = DotNetMetadata.metadataRootOffset(inPE: bytes),
              let reader = DotNetMetadata.MetadataFile(bytes: bytes, root: root) else { return nil }
        return reader.enumTypedProperties()
    }
}

extension DotNetMetadata.MetadataFile {

    /// Le parcours : chaque propriété d'un `PropertyMap`, sa signature, et
    /// l'enum interne qu'elle désigne le cas échéant.
    func enumTypedProperties() -> [String: [String]] {
        // Colonnes de TypeDef : Flags(4) TypeName(str) TypeNamespace(str)
        // Extends(codé) FieldList(→Field) MethodList(→MethodDef).
        let fieldListColumn = 4 + widths.string * 2 + widths.coded(.typeDefOrRef)
        let fieldListWidth = widths.simple(0x04)
        // Colonnes de PropertyMap : Parent(→TypeDef) PropertyList(→Property).
        let parentWidth = widths.simple(0x02)
        let propertyListWidth = widths.simple(0x17)
        // Colonnes de Property : Flags(2) Name(str) Type(blob).
        let propertyTypeColumn = 2 + widths.string

        var result: [String: [String]] = [:]
        var enumCache: [Int: [String]?] = [:]

        for map in 1...max(rowCount[0x15] ?? 0, 1) where (rowCount[0x15] ?? 0) > 0 {
            guard let first = column(table: 0x15, row: map, at: parentWidth,
                                     width: propertyListWidth),
                  let last = listEnd(table: 0x15, row: map, column: parentWidth,
                                     width: propertyListWidth, target: 0x17),
                  first < last else { continue }

            for property in first..<last where property <= (rowCount[0x17] ?? 0) {
                guard let nameIndex = column(table: 0x17, row: property, at: 2, width: widths.string),
                      let name = string(at: nameIndex),
                      let signatureIndex = column(table: 0x17, row: property,
                                                  at: propertyTypeColumn, width: widths.blob),
                      let signature = blob(at: signatureIndex),
                      let typeDefRow = internalValueTypeRow(inPropertySignature: signature)
                else { continue }

                let values: [String]?
                if let cached = enumCache[typeDefRow] {
                    values = cached
                } else {
                    values = enumValues(ofTypeDefRow: typeDefRow,
                                        fieldListColumn: fieldListColumn,
                                        fieldListWidth: fieldListWidth)
                    enumCache[typeDefRow] = values
                }
                // Deux valeurs au minimum : un « choix » à une entrée n'en
                // est pas un, et c'est la règle de l'oracle python.
                if let values, values.count >= 2 {
                    result[name] = values
                }
            }
        }
        return result
    }

    /// La ligne `TypeDef` visée par la signature d'une propriété, quand
    /// celle-ci est un **type valeur de cet assembly**. `nil` pour tout le
    /// reste : scalaires, classes, et types d'un autre assembly (TypeRef).
    ///
    /// §II.23.2.5 — `PROPERTY` (0x08) éventuellement `HASTHIS` (0x20),
    /// nombre de paramètres, modificateurs facultatifs, puis le type.
    func internalValueTypeRow(inPropertySignature signature: [UInt8]) -> Int? {
        var position = 0
        guard position < signature.count, signature[position] & 0x08 == 0x08 else { return nil }
        position += 1
        guard DotNetMetadata.compressedUInt(signature, &position) != nil else { return nil }
        // Modificateurs facultatifs : CMOD_REQD (0x1F) / CMOD_OPT (0x20),
        // chacun suivi d'un TypeDefOrRefOrSpec compressé.
        while position < signature.count, signature[position] == 0x1F || signature[position] == 0x20 {
            position += 1
            guard DotNetMetadata.compressedUInt(signature, &position) != nil else { return nil }
        }
        // ELEMENT_TYPE_VALUETYPE — un enum en est un ; CLASS (0x12) non.
        guard position < signature.count, signature[position] == 0x11 else { return nil }
        position += 1
        guard let token = DotNetMetadata.compressedUInt(signature, &position) else { return nil }
        // TypeDefOrRefOrSpecEncoded : 2 bits de tag, 0 = TypeDef.
        guard token & 0x03 == 0 else { return nil }
        let row = token >> 2
        return row > 0 && row <= (rowCount[0x02] ?? 0) ? row : nil
    }

    /// Les valeurs d'un enum : ses champs **littéraux**, le marqueur
    /// `value__` exigé. Sans ce double filtre, toute classe à champs
    /// passerait pour un enum — c'est la faute qu'a faite le premier
    /// passage de l'extracteur python (89 champs faux, dont les
    /// `<X>k__BackingField` d'auto-propriétés).
    func enumValues(ofTypeDefRow row: Int, fieldListColumn: Int, fieldListWidth: Int) -> [String]? {
        guard let first = column(table: 0x02, row: row, at: fieldListColumn, width: fieldListWidth),
              let last = listEnd(table: 0x02, row: row, column: fieldListColumn,
                                 width: fieldListWidth, target: 0x04),
              first < last else { return nil }

        var values: [String] = []
        var hasValueMarker = false
        for field in first..<last where field <= (rowCount[0x04] ?? 0) {
            guard let flags = column(table: 0x04, row: field, at: 0, width: 2),
                  let nameIndex = column(table: 0x04, row: field, at: 2, width: widths.string),
                  let name = string(at: nameIndex) else { continue }
            if name == "value__" {
                hasValueMarker = true
                continue
            }
            if flags & 0x0040 != 0 {   // fdLiteral
                values.append(name)
            }
        }
        return hasValueMarker ? values : nil
    }
}
