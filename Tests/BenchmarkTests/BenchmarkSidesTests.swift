import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct BenchmarkSidesTests {
    private func mod(_ f: String, id: String, enabled: Bool = true, version: String = "1.0",
                     requires: [String] = []) -> ModItem {
        ModItem(uniqueId: id, name: f, folderName: f, version: version, author: "", description: "",
                nexusUrl: "", nexusModId: "", isEnabled: enabled,
                dependencies: requires.map { ModDependency(uniqueId: $0, isRequired: true) }, languages: [])
    }

    private func group(_ f: String, _ children: [ModItem]) -> ModItem {
        var item = mod(f, id: "")
        item.children = children
        item.isGroup = true
        return item
    }

    @Test func sideAIsTheEnabledTopLevelFolders() {
        let mods = [mod("CP", id: "Pathoschild.ContentPatcher"), mod("Off", id: "x.off", enabled: false),
                    mod("StarHubFR Probe", id: "mrbabilo.StarHubFR.Probe", version: "0.7.0")]
        #expect(BenchmarkSides.foldersA(mods) == ["CP", "StarHubFR Probe"])
    }

    @Test func pauseModRemovesOneFolderAndSameStateKeepsAll() {
        let a = ["CP", "Speedy", "StarHubFR Probe"]
        #expect(BenchmarkSides.foldersB(.pauseMod(folderName: "Speedy"), foldersA: a, mods: []) == ["CP", "StarHubFR Probe"])
        #expect(BenchmarkSides.foldersB(.sameState, foldersA: a, mods: []) == a)
    }

    @Test func profileSideResolvesIdsCaseInsensitively() {
        let mods = [mod("CP", id: "Pathoschild.ContentPatcher"), mod("Probe", id: "mrbabilo.StarHubFR.Probe"),
                    mod("Skip", id: "Pathoschild.SkipIntro", enabled: false)]
        let b = BenchmarkSides.foldersB(.profile(enabledModIds: ["mrbabilo.starhubfr.probe", "PATHOSCHILD.SKIPINTRO"]),
                                        foldersA: ["CP", "Probe"], mods: mods)
        #expect(Set(b) == ["Probe", "Skip"])
    }

    /// Review Focus 5 : un côté B qui ne peut pas tourner est refusé au réglage.
    @Test func refusals() {
        let probe = mod("Probe", id: "mrbabilo.StarHubFR.Probe", version: "0.7.0")
        let cp = mod("CP", id: "Pathoschild.ContentPatcher")
        let pack = mod("[CP] SVE", id: "FlashShifter.SVE", requires: ["Pathoschild.ContentPatcher"])
        #expect(BenchmarkSides.refusal(.sameState, mods: [cp]) == .probeMissing)
        #expect(BenchmarkSides.refusal(.sameState, mods: [mod("Probe", id: "mrbabilo.StarHubFR.Probe", version: "0.6.2")])
                == .probeTooOld("0.6.2"))
        #expect(BenchmarkSides.refusal(.pauseMod(folderName: "Probe"), mods: [probe]) == .probeInSideB)
        #expect(BenchmarkSides.refusal(.profile(enabledModIds: ["Pathoschild.ContentPatcher"]), mods: [probe, cp]) == .probeInSideB)
        #expect(BenchmarkSides.refusal(.pauseMod(folderName: "CP"), mods: [probe, cp, pack]) == .dependents(["[CP] SVE"]))
        #expect(BenchmarkSides.refusal(.pauseMod(folderName: "Nope"), mods: [probe]) == .unknownMod)
        #expect(BenchmarkSides.refusal(.pauseMod(folderName: "[CP] SVE"), mods: [probe, cp, pack]) == nil)
    }

    /// Un framework en pack : l'entrée de tête n'a pas d'identifiant, les
    /// dépendants visent un composant (correction 9 de la relecture).
    @Test func aGroupedFrameworkWithDependentsIsRefused() {
        let probe = mod("Probe", id: "mrbabilo.StarHubFR.Probe", version: "0.7.0")
        let framework = group("Framework", [mod("Framework Core", id: "X.Core"), mod("Framework CP", id: "X.CP")])
        let user = mod("[CP] User", id: "Y.User", requires: ["X.Core"])
        #expect(BenchmarkSides.refusal(.pauseMod(folderName: "Framework"), mods: [probe, framework, user])
                == .dependents(["[CP] User"]))
        #expect(BenchmarkSides.refusal(.pauseMod(folderName: "Framework"), mods: [probe, framework]) == nil)
    }

    /// Relecture finale : la bascule voyage par UniqueID ; un doublon installé
    /// (cas réel — Swim ×2) partirait avec l'original et ne reviendrait pas.
    @Test func aDuplicatedUniqueIdRefusesTheSeries() {
        let probe = mod("Probe", id: "mrbabilo.StarHubFR.Probe", version: "0.7.0")
        let swim = mod("Swim", id: "Swim")
        let twin = mod("Swim Twin", id: "Swim")   // même identifiant, dossier distinct
        let cp = mod("CP", id: "Pathoschild.ContentPatcher")
        #expect(BenchmarkSides.refusal(.sameState, mods: [probe, cp, swim, twin])
                == .duplicateIds(["Swim", "Swim Twin"]))
        #expect(BenchmarkSides.refusal(.sameState, mods: [probe, cp, swim]) == nil)
        #expect(BenchmarkSides.duplicateIdFolders([probe, cp]).isEmpty)
        #expect(BenchmarkSides.duplicateIdFolders([probe, swim, twin]) == ["Swim", "Swim Twin"])
    }

    @Test func cacheWarningNamesSpeedySolutionsWhenItChangesSide() {
        let mods = [mod("Speedy", id: "SinZ.SpeedySolutions"), mod("CP", id: "Pathoschild.ContentPatcher")]
        #expect(BenchmarkSides.cacheWarning(foldersA: ["Speedy", "CP"], foldersB: ["CP"], mods: mods) == ["Speedy"])
        #expect(BenchmarkSides.cacheWarning(foldersA: ["Speedy", "CP"], foldersB: ["Speedy"], mods: mods).isEmpty)
    }

    @Test func probeVersionFloor() {
        #expect(ProbeLoadRecords.version("0.7.0", atLeast: [0, 7, 0]))
        #expect(ProbeLoadRecords.version("0.10.1", atLeast: [0, 7, 0]))
        #expect(!ProbeLoadRecords.version("0.6.2", atLeast: [0, 7, 0]))
        #expect(!ProbeLoadRecords.version("0.7.0-beta", atLeast: [0, 7, 0]))
        #expect(ProbeLoadRecords.writesLoads(probeVersion: "0.6.0"))
    }
}
