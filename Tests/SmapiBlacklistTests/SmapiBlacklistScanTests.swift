import Foundation
import CryptoKit
import Testing
@testable import StarHubTHCore

/// X116 — la forme générée par smapi.io depuis SMAPI `d6f868e`
/// (`MalwareBlacklistConverter`) : entrées par empreinte du DLL d'entrée,
/// avec ou sans `Id`, et fichiers piégés par nom, extension ou empreinte.
/// Les règles sont celles de `ModBlacklist.CheckMod` / `CheckLooseFile` :
/// chaque champ présent doit correspondre, un champ absent ne filtre rien.
@Suite struct SmapiBlacklistScanTests {

    private static func md5(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Exactement la sortie attendue par le test de SMAPI
    /// (`Conversion_ProducesExpectedPublicJson`), empreintes remplacées par
    /// celles des fichiers du parc de test.
    private var generated: Data {
        Data("""
        {"Blacklist":[\
        {"Id":"Author.IdOnly","Message":"Remote code message."},\
        {"Id":"Author.Legit","EntryDllHash":"\(Self.md5("evil"))","Message":"Reupload."},\
        {"EntryDllHash":"\(Self.md5("evil"))","Message":"Hash only."}],\
        "LooseFileBlacklist":[\
        {"Name":"Auto_Alchemistry.bat","Hash":"\(Self.md5("payload"))","Message":"Bat."},\
        {"Extension":".scr","Message":"Screensaver."},\
        {"Hash":"\(Self.md5("anywhere"))","Message":"Hash-only file."}]}
        """.utf8)
    }

    @Test("La forme générée se décode sans perdre une entrée")
    func generatedFormDecodesEveryEntry() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        #expect(dump.entries.count == 3)
        #expect(dump.entries.filter { $0.id == nil }.count == 1)
        #expect(dump.looseFiles.count == 3)
        #expect(dump.looseFiles.contains { $0.extension == ".scr" && $0.name == nil })
    }

    /// Une entrée `Id` + empreinte vise un **reupload** d'un mod légitime :
    /// l'`Id` seul condamnerait le vrai mod. Elle ne se juge qu'avec le DLL.
    @Test("L'identifiant seul ne condamne pas une entrée qui porte une empreinte")
    func idMatchIgnoresHashedEntries() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        #expect(SmapiBlacklist.matches(uniqueIds: ["Author.Legit", "Author.IdOnly"], in: dump).keys.sorted()
                == ["Author.IdOnly"])
    }

    // MARK: - Parc de test

    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blacklist-scan-\(UUID().uuidString)", isDirectory: true)

    private func mod(_ path: String, id: String, entryDll: String? = nil,
                     files: [String: String] = [:]) throws {
        let folder = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dll = entryDll.map { ", \"EntryDll\": \"\($0)\"" } ?? ""
        try "{ \"Name\": \"x\", \"UniqueID\": \"\(id)\"\(dll), }  // JSON5 comme le jeu"
            .write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        for (name, content) in files {
            let url = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Le parc : un mod légitime qui partage l'`Id` du reupload, un mod
    /// piégé rangé dans un pack et en pause, un mod qui porte un `.scr`, un
    /// mod qui porte le bon nom de `.bat` avec un contenu innocent.
    private func library() throws -> [SmapiBlacklistScan.Target] {
        try mod("Legit", id: "Author.Legit", entryDll: "Legit.dll", files: ["Legit.dll": "good"])
        try mod("Pack/.Evil", id: "Other.Evil", entryDll: "Evil.dll", files: ["Evil.dll": "evil"])
        try mod("Tools", id: "Some.Tools", files: ["assets/run.SCR": "x"])
        try mod("Innocent", id: "Some.Innocent", files: ["Auto_Alchemistry.bat": "echo hi"])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("__MACOSX/Evil"),
                                                withIntermediateDirectories: true)
        return SmapiBlacklistScan.targets(modsRoot: root)
    }

    @Test("Les mods se trouvent comme SMAPI : dans un pack, en pause, sans __MACOSX")
    func targetsFollowManifests() throws {
        let targets = try library()
        #expect(targets.map(\.uniqueId).sorted()
                == ["Author.Legit", "Other.Evil", "Some.Innocent", "Some.Tools"])
        #expect(targets.first { $0.uniqueId == "Other.Evil" }?.entryDll == "Evil.dll")
    }

    @Test("L'empreinte du DLL condamne le piégé, pas le légitime au même Id")
    func entryDllHashCondemnsOnlyTheTrappedMod() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        let report = SmapiBlacklistScan.scan(try library(), dump: dump)
        #expect(report.matches["Other.Evil"]?.message == "Hash only.")
        #expect(report.matches["Author.Legit"] == nil)
    }

    @Test("Un fichier piégé par extension est trouvé ; le bon nom au mauvais contenu, non")
    func looseFilesFollowEveryPresentField() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        let report = SmapiBlacklistScan.scan(try library(), dump: dump)
        #expect(report.matches["Some.Tools"]?.message == "Screensaver.")
        #expect(report.matches["Some.Innocent"] == nil)
    }

    /// SMAPI hache chaque fichier de chaque mod pour une entrée d'empreinte
    /// seule ; pas nous (le parc pèse des Go). Elle est **comptée**, jamais
    /// ignorée en silence.
    @Test("Un fichier surveillé par empreinte seule est compté, pas ignoré")
    func hashOnlyLooseEntriesAreCounted() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        #expect(SmapiBlacklistScan.scan(try library(), dump: dump).uncheckedHashOnlyFiles == 1)
    }

    /// Le point d'entrée du ViewModel : identifiants, empreintes et fichiers
    /// fusionnés, et la ligne de journal qui les dit.
    @Test("Le résultat fusionne identifiants et parc, et le dit")
    func runMergesIdAndScanHits() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        _ = try library()
        let outcome = SmapiBlacklistScan.run(dump: dump, uniqueIds: ["Author.IdOnly", "Author.Legit"],
                                             modsRoot: root)
        #expect(outcome.matches.keys.sorted() == ["Author.IdOnly", "Other.Evil", "Some.Tools"])
        #expect(outcome.summary.contains("3 mod(s) malveillant(s)"))
        #expect(outcome.summary.contains("1 fichier(s) surveillé(s) par empreinte seule"))
    }

    /// `Id` **et** empreinte : les deux doivent correspondre. Le même DLL
    /// piégé sous un autre `Id` n'est pas visé par cette entrée-là.
    @Test("Une entrée Id + empreinte ne condamne pas un autre Id au même DLL")
    func idAndHashMustBothMatch() throws {
        let dump = try #require(SmapiBlacklist.decode(Data("""
            {"Blacklist":[{"Id":"Author.Legit","EntryDllHash":"\(Self.md5("evil"))","Message":"m"}]}
            """.utf8)))
        #expect(SmapiBlacklistScan.scan(try library(), dump: dump).matches.isEmpty)
    }

    // MARK: - X118 : le registre des mods déjà vérifiés

    private var registry: URL { root.appendingPathComponent("_registre", isDirectory: true) }

    /// Deuxième passage, rien n'a bougé : seuls les mods signalés se relisent
    /// (jamais inscrits propres), les propres attendent leur changement.
    @Test("Un mod propre et inchangé ne se relit pas")
    func unchangedCleanModsAreSkipped() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        _ = try library()
        let first = SmapiBlacklistScan.run(dump: dump, uniqueIds: [], modsRoot: root, registryDirectory: registry)
        let second = SmapiBlacklistScan.run(dump: dump, uniqueIds: [], modsRoot: root, registryDirectory: registry)
        #expect(first.checked == 4)
        #expect(second.checked == 2)
        #expect(second.matches == first.matches)
    }

    /// Le DLL remplacé (mise à jour, reupload) change l'empreinte du mod.
    @Test("Un DLL qui change fait relire son mod")
    func changedDllIsRechecked() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        _ = try library()
        _ = SmapiBlacklistScan.run(dump: dump, uniqueIds: [], modsRoot: root, registryDirectory: registry)
        try "evil".write(to: root.appendingPathComponent("Legit/Legit.dll"), atomically: true, encoding: .utf8)
        let again = SmapiBlacklistScan.run(dump: dump, uniqueIds: [], modsRoot: root, registryDirectory: registry)
        #expect(again.checked == 3)
    }

    /// Une liste qui change (une entrée neuve), ou un registre de plus de
    /// 24 h, relit tout : une entrée neuve peut viser un mod déjà « propre ».
    @Test("Une liste neuve ou un registre vieux de 24 h relit tout")
    func newListOrOldRegistryRechecksEverything() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        _ = try library()
        let now = Date()
        _ = SmapiBlacklistScan.run(dump: dump, uniqueIds: [], modsRoot: root, registryDirectory: registry, now: now)
        let grown = SmapiBlacklist.Dump(
            entries: dump.entries + [SmapiBlacklist.Entry(id: "New.One", message: "m")],
            looseFiles: dump.looseFiles)
        #expect(SmapiBlacklistScan.run(dump: grown, uniqueIds: [], modsRoot: root,
                                       registryDirectory: registry, now: now).checked == 4)
        #expect(SmapiBlacklistScan.run(dump: grown, uniqueIds: [], modsRoot: root, registryDirectory: registry,
                                       now: now.addingTimeInterval(25 * 3600)).checked == 4)
    }

    /// Sans dossier de données : tout se relit, rien ne s'écrit.
    @Test("Sans dossier de registre, tout se relit à chaque fois")
    func noRegistryDirectoryMeansFullScan() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        _ = try library()
        _ = SmapiBlacklistScan.run(dump: dump, uniqueIds: [], modsRoot: root, registryDirectory: nil)
        #expect(SmapiBlacklistScan.run(dump: dump, uniqueIds: [], modsRoot: root, registryDirectory: nil).checked == 4)
    }

    /// Un DLL d'entrée absent (manifeste qui en nomme un introuvable) : pas
    /// d'empreinte, donc jamais inscrit propre — relu à chaque passage.
    @Test("Un mod sans empreinte lisible se relit toujours")
    func unstampableModIsAlwaysRechecked() throws {
        let dump = try #require(SmapiBlacklist.decode(generated))
        _ = try library()
        try mod("Broken", id: "Some.Broken", entryDll: "Missing.dll")
        _ = SmapiBlacklistScan.run(dump: dump, uniqueIds: [], modsRoot: root, registryDirectory: registry)
        #expect(SmapiBlacklistScan.run(dump: dump, uniqueIds: [], modsRoot: root,
                                       registryDirectory: registry).checked == 3)
    }
}
