import Foundation

/// Lit un `.xnb` de données typées (`Data/Objects`, `BigCraftables`…) en
/// suivant un `XnbSchema`, selon les règles de `ContentReader` et
/// `ReflectiveReader` :
/// - type référence (chaîne, liste, dictionnaire, objet) : index de reader
///   7-bit, `0` = `null`, puis le contenu ; le reader désigné doit être
///   celui que le schéma attend, sinon `schemaMismatch` ;
/// - type valeur (`int`, `bool`, `float`, `double`, énumération, `Nullable`)
///   lu nu dans un objet, une liste ou un dictionnaire ;
/// - liste et dictionnaire : compte `u32` LE puis les éléments ;
/// - l'objet racine est toujours précédé de son index de reader.
///
/// Les erreurs du conteneur (`XnbContainer.open`) restent celles de
/// `XnbStringDictionaryReader.ReadError` ; celles du contenu sont les
/// siennes. Un XNB d'une autre version du jeu échoue en erreur nommée,
/// jamais par une allocation géante ni un résultat partiel.
public enum XnbTypedReader {
    public enum ReadError: Error, Equatable, Sendable {
        /// Le reader déclaré n'est pas celui du schéma (`expectedReader` en
        /// forme courte, `found` tel qu'écrit dans le fichier).
        case schemaMismatch(expectedReader: String, found: String)
        /// Compte d'éléments ou longueur de chaîne déraisonnable.
        case countTooLarge(Int)
        case truncated
        /// Octets restants après l'objet racine : le schéma ne couvre pas tout.
        case trailingBytes(Int)
    }

    /// Plafond d'un compte de liste ou de dictionnaire (`Data/Objects` en
    /// compte moins de 2 000).
    private static let maxCount = 250_000

    public static func read(_ data: Data, root: XnbSchema) throws -> XnbValue {
        let (readers, cursor) = try XnbContainer.open(data)
        var decoder = Decoder(readers: readers, cursor: cursor)
        let value: XnbValue
        do {
            value = try decoder.reference(root)
        } catch XnbStringDictionaryReader.ReadError.truncated {
            throw ReadError.truncated
        } catch XnbStringDictionaryReader.ReadError.stringTooLong(let length) {
            throw ReadError.countTooLarge(length)
        }
        guard decoder.cursor.remaining == 0 else {
            throw ReadError.trailingBytes(decoder.cursor.remaining)
        }
        return value
    }

    private struct Decoder {
        let readers: [String]
        var cursor: XnbCursor

        /// Index de reader 7-bit (1-based, `0` = `null`), vérifié, puis contenu.
        mutating func reference(_ schema: XnbSchema) throws -> XnbValue {
            let index = try cursor.vint()
            guard index != 0 else { return .null }
            let expected = schema.expectedReader
            guard index <= readers.count else {
                throw ReadError.schemaMismatch(
                    expectedReader: expected.description,
                    found: "reader \(index) of \(readers.count)")
            }
            let written = readers[index - 1]
            guard expected.matches(written) else {
                throw ReadError.schemaMismatch(expectedReader: expected.description, found: written)
            }
            return try content(schema)
        }

        /// Un membre, un élément ou une clé : nu si type valeur.
        mutating func member(_ schema: XnbSchema) throws -> XnbValue {
            schema.isValueType ? try content(schema) : try reference(schema)
        }

        mutating func content(_ schema: XnbSchema) throws -> XnbValue {
            switch schema {
            case .string:
                return .string(try cursor.string())
            case .int, .enumInt:
                return .int(try cursor.i32LE())
            case .bool:
                return .bool(try cursor.byte() != 0)
            case .float:
                return .float(try cursor.f32LE())
            case .double:
                return .double(try cursor.f64LE())
            case .nullable(let inner):
                return try cursor.byte() != 0 ? try content(inner) : .null
            case .list(let element):
                let count = try self.count()
                var items: [XnbValue] = []
                items.reserveCapacity(count)
                for _ in 0..<count { items.append(try member(element)) }
                return .list(items)
            case .dictionary(let key, let value):
                let count = try self.count()
                var pairs: [XnbPair] = []
                pairs.reserveCapacity(count)
                for _ in 0..<count {
                    let pairKey = try member(key)
                    pairs.append(XnbPair(key: pairKey, value: try member(value)))
                }
                return .dictionary(pairs)
            case .object(_, let members):
                var fields: [String: XnbValue] = [:]
                for (name, memberSchema) in members {
                    fields[name] = try member(memberSchema)
                }
                return .object(fields)
            }
        }

        /// Compte `u32` LE, plafonné avant toute allocation. Chaque élément
        /// occupe au moins un octet : un compte qui dépasse les octets
        /// restants est faux.
        private mutating func count() throws -> Int {
            let count = Int(try cursor.u32LE())
            guard count <= XnbTypedReader.maxCount, count <= cursor.remaining else {
                throw ReadError.countTooLarge(count)
            }
            return count
        }
    }
}
