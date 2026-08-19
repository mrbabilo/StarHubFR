import Testing
@testable import StarHubTHCore

struct LzxdWindowTests {
    @Test func pastViewReturnsWhatWasPushedInOrder() {
        var w = LzxdWindowSize.kb64.makeWindow()
        for b in [UInt8(1), 2, 3, 4, 5] { w.push(b) }
        #expect(Array(w.pastView(5)) == [1, 2, 3, 4, 5])
        #expect(Array(w.pastView(2)) == [4, 5])
    }

    @Test func copyFromSelfHonorsOffsetAndOverlap() {
        var w = LzxdWindowSize.kb64.makeWindow()
        for b in [UInt8(1), 2, 3, 4, 5] { w.push(b) }
        w.copyFromSelf(offset: 3, length: 4)
        // Offset 3 = trois octets en arrière : 3, 4, 5, puis le 3 re-copié
        // par le chevauchement — la répétition « aaa » d'un flux réel.
        #expect(Array(w.pastView(4)) == [3, 4, 5, 3])
    }

    @Test func copyFromSelfOffsetOneRepeatsLastByte() {
        // Offset 1 = « le dernier octet écrit » : le chevauchement fabrique
        // la répétition immédiate (RLE), interdite à la copie par blocs.
        var w = LzxdWindowSize.kb64.makeWindow()
        for b in [UInt8(1), 2, 3, 4, 5] { w.push(b) }
        w.copyFromSelf(offset: 1, length: 4)
        #expect(Array(w.pastView(4)) == [5, 5, 5, 5])
    }

    @Test func windowWrapsAndKeepsHistory() {
        var w = LzxdWindowSize.kb64.makeWindow()
        // 258 cycles de 256 = 66 048 écritures : `pos` a rebouclé.
        for _ in 0..<258 { for b in UInt8(0)...255 { w.push(b) } }
        #expect(Array(w.pastView(3)) == [253, 254, 255])
        // La vue maximale autorisée est MAX_CHUNK_SIZE (32 Ko), pas la
        // taille de la fenêtre — `past_view` du Rust le refuse au-delà.
        #expect(w.pastView(LzxdWindowSize.maxChunkSize).count
            == LzxdWindowSize.maxChunkSize)
    }

    @Test func copyFromBitstreamReadsRawBytes() throws {
        var stream = LzxdBitstream([0xAA, 0xBB, 0xCC])
        var w = LzxdWindowSize.kb64.makeWindow()
        try w.copyFromBitstream(&stream, length: 3)
        #expect(Array(w.pastView(3)) == [0xAA, 0xBB, 0xCC])
        #expect(stream.remainingBytes == 0)
    }

    @Test func copyFromBitstreamShiftsRoomAtTheBoundary() throws {
        // Écriture chevauchant la fin du tampon : la fin est déplacée vers
        // le début pour que la lecture soit contiguë (`check_bitstream_at_boundary`).
        var stream = LzxdBitstream([1, 2, 3, 4])
        var w = LzxdWindowSize.kb64.makeWindow()
        for _ in 0..<(LzxdWindowSize.kb64.byteCount - 2) { w.push(0) }
        try w.copyFromBitstream(&stream, length: 4)
        #expect(Array(w.pastView(4)) == [1, 2, 3, 4])
    }

    @Test func copyFromBitstreamRejectsMoreThanTheWindow() {
        var stream = LzxdBitstream([0x00])
        var w = LzxdWindowSize.kb64.makeWindow()
        #expect(throws: LzxdWindow.Error.windowTooSmall) {
            try w.copyFromBitstream(&stream, length: LzxdWindowSize.kb64.byteCount + 1)
        }
    }

    @Test func sizesAndSlotsMatchTheRust() {
        #expect(LzxdWindowSize.kb32.byteCount == 32 * 1024)
        #expect(LzxdWindowSize.kb64.byteCount == 64 * 1024)
        #expect(LzxdWindowSize.kb32.positionSlots == 30)
        #expect(LzxdWindowSize.kb64.positionSlots == 32)
    }
}
