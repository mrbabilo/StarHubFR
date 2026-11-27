import Foundation
import Testing
@testable import StarHubTHCore

/// Lecteur typé guidé par schéma : chaque règle du format
/// (`ContentReader` / `ReflectiveReader`) testée sur un XNB fabriqué.
struct XnbTypedReaderTests {
    // Noms de readers tels que le jeu les écrit (types qualifiés par leur
    // assembly) ; le lecteur doit les reconnaître sans ces qualificatifs.
    static let corlib = "mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089"
    static let stringReader = "Microsoft.Xna.Framework.Content.StringReader"
    static let listOfStrings =
        "Microsoft.Xna.Framework.Content.ListReader`1[[System.String, \(corlib)]]"
    static let item = "Game.Item"
    static func reflective(_ type: String) -> String {
        "Microsoft.Xna.Framework.Content.ReflectiveReader`1[[\(type), Game, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null]]"
    }

    typealias Fixture = XnbFixture

    /// Un fichier : readers déclarés, index racine 1, puis le contenu.
    static func file(_ readers: [String], _ content: [UInt8]) -> Data {
        Fixture.xnb(content: Fixture.body(readers: readers, rootIndex: 1, entryBytes: content))
    }

    static func f32(_ value: Float) -> [UInt8] { Fixture.u32(Int(value.bitPattern)) }
    static func f64(_ value: Double) -> [UInt8] {
        (0..<8).map { UInt8((value.bitPattern >> (8 * UInt64($0))) & 0xFF) }
    }

    @Test func nullReferenceIsZero() throws {
        let schema = XnbSchema.object(name: Self.item, members: [("Name", .string)])
        let data = Self.file([Self.reflective(Self.item), Self.stringReader], [0])
        #expect(try XnbTypedReader.read(data, root: schema) == .object(["Name": .null]))
    }

    @Test func valueTypesAreReadRaw() throws {
        let schema = XnbSchema.object(name: Self.item, members: [
            ("Price", .int), ("Edible", .bool), ("Scale", .float), ("Weight", .double),
        ])
        let content = Fixture.u32(-7 & 0xFFFFFFFF) + [1] + Self.f32(1.5) + Self.f64(-2.25)
        let data = Self.file([Self.reflective(Self.item)], content)
        #expect(try XnbTypedReader.read(data, root: schema) == .object([
            "Price": .int(-7), "Edible": .bool(true), "Scale": .float(1.5), "Weight": .double(-2.25),
        ]))
    }

    @Test func nullableIntHasFlag() throws {
        let schema = XnbSchema.object(name: Self.item, members: [
            ("Set", .nullable(.int)), ("Unset", .nullable(.int)),
        ])
        let data = Self.file([Self.reflective(Self.item)], [1] + Fixture.u32(5) + [0])
        #expect(try XnbTypedReader.read(data, root: schema) == .object([
            "Set": .int(5), "Unset": .null,
        ]))
    }

    @Test func enumIsInt32() throws {
        let schema = XnbSchema.object(name: Self.item, members: [("Kind", .enumInt), ("Next", .bool)])
        let data = Self.file([Self.reflective(Self.item)], Fixture.u32(3) + [0])
        #expect(try XnbTypedReader.read(data, root: schema) == .object([
            "Kind": .int(3), "Next": .bool(false),
        ]))
    }

    @Test func listOfStrings() throws {
        let content = Fixture.u32(2) + [2] + Fixture.string("a") + [0]
        let data = Self.file([Self.listOfStrings, Self.stringReader], content)
        #expect(try XnbTypedReader.read(data, root: .list(.string)) == .list([.string("a"), .null]))
    }

    @Test func dictionaryStringToObject() throws {
        let dictionary = "Microsoft.Xna.Framework.Content.DictionaryReader`2[[System.String, \(Self.corlib)],[\(Self.item), Game, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null]]"
        let schema = XnbSchema.dictionary(key: .string, value: .object(
            name: Self.item, members: [("Name", .string), ("Price", .int)]))
        var content = Fixture.u32(1)
        content += [2] + Fixture.string("24")
        content += [3] + [2] + Fixture.string("Parsnip") + Fixture.u32(35)
        let data = Self.file([dictionary, Self.stringReader, Self.reflective(Self.item)], content)
        #expect(try XnbTypedReader.read(data, root: schema) == .dictionary([
            XnbPair(key: .string("24"), value: .object(["Name": .string("Parsnip"), "Price": .int(35)])),
        ]))
    }

    /// Les membres se lisent dans l'ordre du schéma : la classe de base
    /// (`BaseId`) avant la classe dérivée (`Own`).
    @Test func baseClassFieldsComeFirst() throws {
        let schema = XnbSchema.object(name: Self.item, members: [("BaseId", .int), ("Own", .int)])
        let data = Self.file([Self.reflective(Self.item)], Fixture.u32(1) + Fixture.u32(2))
        #expect(try XnbTypedReader.read(data, root: schema) == .object([
            "BaseId": .int(1), "Own": .int(2),
        ]))
    }

    /// Dans une classe, la propriété `Id` (référence, index de reader) avant
    /// le champ `Count` (valeur nue).
    @Test func propertiesBeforeFields() throws {
        let schema = XnbSchema.object(name: Self.item, members: [("Id", .string), ("Count", .int)])
        let content = [2] + Fixture.string("x") + Fixture.u32(9)
        let data = Self.file([Self.reflective(Self.item), Self.stringReader], content)
        #expect(try XnbTypedReader.read(data, root: schema) == .object([
            "Id": .string("x"), "Count": .int(9),
        ]))
    }

    @Test func absurdCountIsAnError() {
        let data = Self.file([Self.listOfStrings, Self.stringReader], Fixture.u32(0x7FFF_FFFF))
        #expect(throws: XnbTypedReader.ReadError.countTooLarge(0x7FFF_FFFF)) {
            _ = try XnbTypedReader.read(data, root: .list(.string))
        }
    }

    @Test func leftoverBytesAreAnError() {
        let data = Self.file([Self.listOfStrings, Self.stringReader], Fixture.u32(0) + [0xAB])
        #expect(throws: XnbTypedReader.ReadError.trailingBytes(1)) {
            _ = try XnbTypedReader.read(data, root: .list(.string))
        }
    }

    @Test func wrongReaderIsSchemaMismatch() {
        let data = Self.file([Self.listOfStrings, Self.stringReader], Fixture.u32(0))
        #expect(throws: XnbTypedReader.ReadError.schemaMismatch(
            expectedReader: "Microsoft.Xna.Framework.Content.ListReader`1[[System.Int32]]",
            found: Self.listOfStrings)) {
            _ = try XnbTypedReader.read(data, root: .list(.int))
        }
    }

    @Test func missingBytesAreTruncated() {
        let schema = XnbSchema.object(name: Self.item, members: [("Price", .int)])
        let data = Self.file([Self.reflective(Self.item)], [1, 2])
        #expect(throws: XnbTypedReader.ReadError.truncated) {
            _ = try XnbTypedReader.read(data, root: schema)
        }
    }
}
