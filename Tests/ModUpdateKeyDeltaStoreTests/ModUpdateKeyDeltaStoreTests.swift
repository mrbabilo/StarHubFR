import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct ModUpdateKeyDeltaStoreTests {

    private var dir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("store-\(UUID().uuidString)")
    }
    private let sample: ModUpdateKeyDelta = ModUpdateKeyDelta(
        uniqueId: "a.b", folderName: "Mod", date: Date(timeIntervalSince1970: 1000),
        config: KeySetDelta(added: ["New": "1"], removed: [:], reconciled: []),
        translation: TranslationKeyDelta(addedUntranslated: ["k": "v"],
                                         addedAuthorTranslated: [:],
                                         removedKeys: [:], reconciled: []))

    @Test func saveThenLoadRoundTrips() throws {
        let d = dir
        try ModUpdateKeyDeltaStore.save(sample, directory: d)
        let back = ModUpdateKeyDeltaStore.load(uniqueId: "a.b", directory: d)
        #expect(back == sample)
    }

    @Test func saveOverwritesDoesNotAppend() throws {
        let d = dir
        try ModUpdateKeyDeltaStore.save(sample, directory: d)
        var second = sample
        second.translation.addedUntranslated["other"] = "w"
        try ModUpdateKeyDeltaStore.save(second, directory: d)
        let back = ModUpdateKeyDeltaStore.load(uniqueId: "a.b", directory: d)
        #expect(back == second, "une écriture, pas un append — dernier delta seulement")
        let files = try FileManager.default.contentsOfDirectory(atPath: d.path)
        #expect(files.count == 1)
    }

    @Test func removePurges() throws {
        let d = dir
        try ModUpdateKeyDeltaStore.save(sample, directory: d)
        ModUpdateKeyDeltaStore.remove(uniqueId: "a.b", directory: d)
        #expect(ModUpdateKeyDeltaStore.load(uniqueId: "a.b", directory: d) == nil)
    }

    @Test func nilDirectoryAndCorruptFileAreSilent() throws {
        #expect(ModUpdateKeyDeltaStore.load(uniqueId: "a.b", directory: nil) == nil)
        let d = dir
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data("pas un json".utf8).write(to: d.appendingPathComponent("a.b.json"))
        #expect(ModUpdateKeyDeltaStore.load(uniqueId: "a.b", directory: d) == nil)
    }
}
