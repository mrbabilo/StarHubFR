import Testing
import Foundation
@testable import StarHubTHCore

/// X138 — PureBinarySave charge `<partie>.bin` dès qu'il existe, sans
/// regarder le XML. Ce que l'app écrit dans le XML doit donc écarter ce
/// `.bin`, sans jamais écarter la seule copie complète de la partie.
struct PureBinarySaveTests {
    private let complete = Data(("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<SaveGame xmlns:xsi=\"x\">"
        + String(repeating: "<item />", count: 80) + "</SaveGame>").utf8)
    private let stub = Data("<!-- PureBinarySave -->\n<PureBinarySave active=\"true\"/>".utf8)
    private let info = Data(("<?xml version=\"1.0\"?>\n<Farmer>" + String(repeating: "<a />", count: 120) + "</Farmer>").utf8)

    /// Un dossier de partie `Ferme_1` dans un répertoire temporaire.
    private func saveFolder(xml: Data, binAge: TimeInterval? = nil) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("Ferme_1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let main = folder.appendingPathComponent("Ferme_1")
        try xml.write(to: main)
        if let binAge {
            for name in ["Ferme_1.bin", "Ferme_1.bin.bak", "SaveGameInfo.bin", "Ferme_1.fr-FR.assets.bin"] {
                let url = folder.appendingPathComponent(name)
                try Data("PPBS".utf8).write(to: url)
                try FileManager.default.setAttributes(
                    [.modificationDate: Date().addingTimeInterval(binAge)], ofItemAtPath: url.path)
            }
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: main.path)
        }
        return folder
    }

    private func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    @Test func aCompleteSaveIsRecognisedByItsRoot() {
        #expect(PureBinarySave.isCompleteSave(complete))
        #expect(!PureBinarySave.isCompleteSave(stub))
        #expect(!PureBinarySave.isCompleteSave(info))
        #expect(PureBinarySave.isCompleteSave(Data([0xEF, 0xBB, 0xBF]) + complete))
    }

    @Test func withoutABinEverySaveIsEditable() throws {
        let folder = try saveFolder(xml: stub)
        #expect(PureBinarySave.allowsEditing(folder.appendingPathComponent("Ferme_1")))
    }

    /// Au coucher, le XML n'est qu'un talon : la partie est dans le `.bin`.
    @Test func aStubNextToABinIsNotEditable() throws {
        let folder = try saveFolder(xml: stub, binAge: -60)
        #expect(!PureBinarySave.allowsEditing(folder.appendingPathComponent("Ferme_1")))
    }

    /// Un `.bin` plus récent que le XML : le mod reconstruirait le XML depuis
    /// lui au lancement, et l'écarter perdrait la partie la plus récente.
    @Test func aBinNewerThanTheXMLKeepsTheSaveLocked() throws {
        let folder = try saveFolder(xml: complete, binAge: 60)
        #expect(!PureBinarySave.allowsEditing(folder.appendingPathComponent("Ferme_1")))
    }

    @Test func writingACompleteSaveSetsTheBinFilesAside() throws {
        let folder = try saveFolder(xml: complete, binAge: -60)
        let main = folder.appendingPathComponent("Ferme_1")
        #expect(PureBinarySave.allowsEditing(main))
        var removed: [String] = []
        try PureBinarySave.write(complete, to: main) { url in
            removed.append(url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
        }
        #expect(Set(removed) == ["Ferme_1.bin", "Ferme_1.bin.bak", "SaveGameInfo.bin"])
        #expect(names(in: folder) == ["Ferme_1", "Ferme_1.fr-FR.assets.bin"])
        #expect(try Data(contentsOf: main) == complete)
    }

    /// `SaveGameInfo` n'est pas la partie : l'écrire ne touche pas aux `.bin`.
    @Test func writingAnythingElseLeavesTheBinFiles() throws {
        let folder = try saveFolder(xml: complete, binAge: -60)
        var removed: [URL] = []
        try PureBinarySave.write(info, to: folder.appendingPathComponent("SaveGameInfo")) { removed.append($0) }
        try PureBinarySave.write(stub, to: folder.appendingPathComponent("Ferme_1")) { removed.append($0) }
        #expect(removed.isEmpty)
    }

    private func mod(_ name: String, id: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: name, folderName: name, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], languages: [])
    }

    @Test func warnsOnlyWhenActiveWithoutAnActiveSpaceCore() {
        let pbs = mod("PureBinarySave", id: "palmhacker13.purebinarysave")
        let issues = PureBinarySave.issues([pbs], { "[\($0)]" })
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .critical)
        #expect(issues.first?.source == .pureBinarySave)
        #expect(issues.first?.title == "[\(PureBinarySave.titleKey)]")
        #expect(issues.first?.actions == [.openMod(query: "PureBinarySave")])
        #expect(PureBinarySave.issues([pbs, mod("SpaceCore", id: "spacechase0.SpaceCore", enabled: false)], { $0 }).count == 1)
        #expect(PureBinarySave.issues([pbs, mod("SpaceCore", id: "spacechase0.SpaceCore")], { $0 }).isEmpty)
        #expect(PureBinarySave.issues([mod("PureBinarySave", id: "palmhacker13.PureBinarySave", enabled: false)], { $0 }).isEmpty)
    }

    /// 1.0.8 corrige l'écriture au coucher sans SpaceCore ou sur macOS
    /// (journal de l'auteur, relevé le 2026-11-03) : plus d'alerte au-delà.
    @Test func theFixedVersionsAreNotFlagged() {
        func pbs(_ version: String) -> ModItem {
            ModItem(uniqueId: "palmhacker13.PureBinarySave", name: "PureBinarySave", folderName: "PureBinarySave",
                    version: version, author: "", description: "", nexusUrl: "", nexusModId: "",
                    isEnabled: true, dependencies: [], languages: [])
        }
        #expect(PureBinarySave.issues([pbs("1.0.7")], { $0 }).count == 1)
        #expect(PureBinarySave.issues([pbs("1.0.8")], { $0 }).isEmpty)
        #expect(PureBinarySave.issues([pbs("1.0.9")], { $0 }).isEmpty)
        #expect(PureBinarySave.issues([pbs("1.1.0")], { $0 }).isEmpty)
    }
}
