import Foundation
import Testing
@testable import StarHubTHCore

struct XnbContainerTests {
    @Test func containerListsTheReadersAndStopsOnTheRootIndex() throws {
        let file = XnbFixture.xnb(content: XnbFixture.body(
            rootIndex: 2, entryBytes: [0x2A]))
        let (readers, opened) = try XnbContainer.open(file)
        var cursor = opened
        #expect(readers == [XnbFixture.dictionaryName, XnbFixture.stringReaderName])
        #expect(try cursor.vint() == 2)      // l’index du lecteur racine
        #expect(try cursor.byte() == 0x2A)
        #expect(cursor.remaining == 0)
    }

    @Test func cursorReadsFixedWidthLittleEndianValues() throws {
        var bytes: [UInt8] = [7]
        bytes += XnbFixture.u32(0x01020304)
        bytes += XnbFixture.u32(-2 & 0xFFFFFFFF)
        bytes += [0x00, 0x00, 0xC0, 0x3F]                          // 1.5f
        bytes += [0, 0, 0, 0, 0, 0, 0xF8, 0x3F]                    // 1.5
        bytes += XnbFixture.vint(300) + XnbFixture.string("abc")
        var cursor = XnbCursor(bytes: bytes)
        #expect(try cursor.byte() == 7)
        #expect(try cursor.u32LE() == 0x01020304)
        #expect(try cursor.i32LE() == -2)
        #expect(try cursor.f32LE() == 1.5)
        #expect(try cursor.f64LE() == 1.5)
        #expect(try cursor.vint() == 300)
        #expect(try cursor.string() == "abc")
        #expect(cursor.remaining == 0)
        #expect(throws: XnbStringDictionaryReader.ReadError.truncated) {
            _ = try cursor.byte()
        }
    }

    @Test func containerRejectsSharedResources() {
        let file = XnbFixture.xnb(content: XnbFixture.body(
            sharedResources: 1, entryBytes: []))
        #expect(throws: XnbStringDictionaryReader.ReadError.sharedResourcesUnsupported) {
            _ = try XnbContainer.open(file)
        }
    }
}
