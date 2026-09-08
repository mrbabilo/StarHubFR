import Foundation
import Testing
@testable import StarHubTHCore

/// C2-T4 §4 — la préservation à l'update ne doit pas figer l'anglais du mod :
/// `i18n/default.json` et `i18n/en.json` sont le texte de l'auteur, pas des
/// données utilisateur. B4-T4 les avait embarqués dans le lot en filtrant par
/// nom, récursivement.
@Suite struct UpdateKeyPreservationTests {

    /// Écrit un fichier sous `base/relativePath`, créant les dossiers.
    private func write(_ content: String, base: URL, relativePath: String) throws {
        let url = base.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(toFile: url.path, atomically: true, encoding: .utf8)
    }

    private func read(_ relativePath: String, under base: URL) throws -> String {
        try String(contentsOf: base.appendingPathComponent(relativePath),
                   encoding: .utf8)
    }

    @Test func authorsDefaultJsonIsReplacedByTheUpdate() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // Ancien installé : un anglais pauvre, un français utilisateur.
        try makeModFolder(base: env.modsDir, relativePath: "SampleMod",
                          uniqueId: "a.sample", name: "Sample")
        try write(#"{"only.old":"Ancien texte"}"#, base: env.modsDir,
                  relativePath: "SampleMod/i18n/default.json")
        try write(#"{"only.old":"Vieille traduction"}"#, base: env.modsDir,
                  relativePath: "SampleMod/i18n/fr.json")

        // Archive neuve : anglais enrichi, son propre fr.json (qui sera écarté
        // par la préservation — comportement conservé).
        try makeModFolder(base: env.tempExtractDir, relativePath: "SampleMod",
                          uniqueId: "a.sample", name: "Sample")
        try write(#"{"only.old":"Texte corrigé","new.key":"Texte neuf"}"#,
                  base: env.tempExtractDir, relativePath: "SampleMod/i18n/default.json")
        try write(#"{"new.key":"Traduction de l'auteur"}"#,
                  base: env.tempExtractDir, relativePath: "SampleMod/i18n/fr.json")

        let existing = ModItem(uniqueId: "a.sample", name: "Sample",
                               folderName: "SampleMod", version: "1.0.0",
                               author: "A", description: "", nexusUrl: "",
                               nexusModId: "", isEnabled: true, dependencies: [],
                               children: nil, isGroup: false)
        let mod = DetectedMod(folderName: "SampleMod", relativePath: "SampleMod",
                              manifest: parsedManifest(uniqueId: "a.sample", name: "Sample"),
                              hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                              existingVersion: existing)
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: .overwriteWithBackup)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        _ = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                  selections: [selection], detectedMods: [mod],
                                  gameDir: env.gameDir, existingMods: [existing])

        // L'anglais du disque est celui du NEUF (corrigé, clé neuve présente)…
        let english = try read("SampleMod/i18n/default.json", under: env.modsDir)
        #expect(english.contains("Texte corrigé"), "l'anglais ancien a été restauré par-dessus le neuf")
        #expect(english.contains("new.key"), "la clé anglaise neuve manque : l'anglais du mod est figé")

        // …et le français utilisateur traverse toujours.
        let french = try read("SampleMod/i18n/fr.json", under: env.modsDir)
        #expect(french.contains("Vieille traduction"), "le fr.json utilisateur n'a pas été préservé")
    }

    @Test func packComponentEnglishIsReplacedToo() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.modsDir, relativePath: "Pack/Kid",
                          uniqueId: "a.kid", name: "Kid")
        try write(#"{"old":"v1"}"#, base: env.modsDir,
                  relativePath: "Pack/Kid/i18n/default.json")

        try makeModFolder(base: env.tempExtractDir, relativePath: "Pack/Kid",
                          uniqueId: "a.kid", name: "Kid")
        try write(#"{"old":"v2","plus":"neuf"}"#, base: env.tempExtractDir,
                  relativePath: "Pack/Kid/i18n/default.json")

        let existing = ModItem(uniqueId: "a.kid", name: "Kid", folderName: "Pack/Kid",
                               version: "1.0.0", author: "A", description: "",
                               nexusUrl: "", nexusModId: "", isEnabled: true,
                               dependencies: [], children: nil, isGroup: false)
        let mod = DetectedMod(folderName: "Kid", relativePath: "Pack/Kid",
                              manifest: parsedManifest(uniqueId: "a.kid", name: "Kid"),
                              hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                              existingVersion: existing)
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: .overwriteWithBackup)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        _ = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                  selections: [selection], detectedMods: [mod],
                                  gameDir: env.gameDir, existingMods: [existing])

        let english = try read("Pack/Kid/i18n/default.json", under: env.modsDir)
        #expect(english.contains("v2") && english.contains("plus"),
                "l'anglais d'un composant de pack reste figé à l'ancienne version")
    }

    @Test func rootLevelDefaultJsonIsStillPreserved() throws {
        // Un `default.json` hors `i18n/` n'est pas un texte de mod : il reste
        // préservé comme aujourd'hui (le filtre est chirurgical, par chemin).
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.modsDir, relativePath: "Cfg",
                          uniqueId: "a.cfg", name: "Cfg")
        try write(#"{"keep":"user"}"#, base: env.modsDir, relativePath: "Cfg/default.json")
        try write(#"{"keep":"old"}"#, base: env.modsDir, relativePath: "Cfg/config.json")

        try makeModFolder(base: env.tempExtractDir, relativePath: "Cfg",
                          uniqueId: "a.cfg", name: "Cfg")
        try write(#"{"keep":"author"}"#, base: env.tempExtractDir, relativePath: "Cfg/default.json")
        try write(#"{"keep":"author"}"#, base: env.tempExtractDir, relativePath: "Cfg/config.json")

        let existing = ModItem(uniqueId: "a.cfg", name: "Cfg", folderName: "Cfg",
                               version: "1.0.0", author: "A", description: "",
                               nexusUrl: "", nexusModId: "", isEnabled: true,
                               dependencies: [], children: nil, isGroup: false)
        let mod = DetectedMod(folderName: "Cfg", relativePath: "Cfg",
                              manifest: parsedManifest(uniqueId: "a.cfg", name: "Cfg"),
                              hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                              existingVersion: existing)
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: .overwriteWithBackup)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        _ = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                  selections: [selection], detectedMods: [mod],
                                  gameDir: env.gameDir, existingMods: [existing])

        #expect(try read("Cfg/default.json", under: env.modsDir).contains("user"),
                "un default.json racine doit rester préservé")
        #expect(try read("Cfg/config.json", under: env.modsDir).contains("old"),
                "le config.json doit rester préservé")
    }
}
