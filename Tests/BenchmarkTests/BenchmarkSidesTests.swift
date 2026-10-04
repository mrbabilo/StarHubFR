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

    /// Ce que le panneau du benchmark annonce comme « ce qui change entre A et B » :
    /// le nom affiché du mod mis en pause, la taille du profil, ou le bruit.
    @Test func theABChangeNamesTheModOrCountsTheProfile() {
        let mods = [mod("Speedy", id: "sinz.speedysolutions"), mod("CP", id: "Pathoschild.ContentPatcher")]
        #expect(BenchmarkSides.change(for: .pauseMod(folderName: "Speedy"), mods: mods) == .pauseMod(modName: "Speedy"))
        // Dossier sans correspondance : le dossier lui-même, jamais une chaîne vide.
        #expect(BenchmarkSides.change(for: .pauseMod(folderName: "Fantôme"), mods: mods) == .pauseMod(modName: "Fantôme"))
        #expect(BenchmarkSides.change(for: .profile(enabledModIds: ["a", "b", "c", "d"]), mods: mods) == .profile(modCount: 4))
        #expect(BenchmarkSides.change(for: .sameState, mods: mods) == .sameState)
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

    /// État A = un profil de base (« BENCHMARK ») : le parc vu comme si ce
    /// profil était actif — même règle que `foldersB(.profile)`, un pack est
    /// actif si l'un de ses composants est dans le profil.
    @Test func stateAFromABaseProfile() {
        let probe = mod("Probe", id: "mrbabilo.StarHubFR.Probe", version: "0.7.0")
        let skip = mod("Skip", id: "Pathoschild.SkipIntro", enabled: false)
        let cp = mod("CP", id: "Pathoschild.ContentPatcher")
        let pack = group("Pack", [mod("Pack Core", id: "X.Core", enabled: false), mod("Pack CP", id: "X.CP", enabled: false)])
        let mods = [probe, skip, cp, pack]
        #expect(BenchmarkSides.stateA(mods, baseProfileIds: nil) == mods)
        let view = BenchmarkSides.stateA(mods, baseProfileIds: ["mrbabilo.starhubfr.probe", "PATHOSCHILD.SKIPINTRO", "X.CP"])
        #expect(BenchmarkSides.foldersA(view) == ["Probe", "Skip", "Pack"])
        #expect(view.first { $0.folderName == "Pack" }?.children?.allSatisfy(\.isEnabled) == true)
        // B se calcule depuis A : mettre en pause un mod du profil de base.
        #expect(BenchmarkSides.foldersB(.pauseMod(folderName: "Skip"), foldersA: BenchmarkSides.foldersA(view), mods: view)
                == ["Probe", "Pack"])
    }

    /// Les refus jugent l'état A, pas le parc actif : un profil de base sans
    /// la sonde ne mesurerait rien. Les doublons du parc réel comptent quand
    /// même — la restauration le rebascule en entier.
    @Test func refusalsJudgeTheBaseProfile() {
        let probe = mod("Probe", id: "mrbabilo.StarHubFR.Probe", version: "0.7.0")
        let cp = mod("CP", id: "Pathoschild.ContentPatcher")
        let swim = mod("Swim", id: "Swim")
        let twin = mod("Swim Twin", id: "Swim")
        #expect(BenchmarkSides.refusal(.sameState, mods: [probe, cp], baseProfileIds: ["Pathoschild.ContentPatcher"])
                == .probeMissing)
        #expect(BenchmarkSides.refusal(.sameState, mods: [probe, cp], baseProfileIds: [BenchmarkSides.probeId]) == nil)
        #expect(BenchmarkSides.refusal(.sameState, mods: [probe, cp, swim, twin], baseProfileIds: [BenchmarkSides.probeId])
                == .duplicateIds(["Swim", "Swim Twin"]))
        // Un mod en pause dans le parc, actif dans le profil : sa pause en B est jugée sur A.
        let off = mod("Off", id: "Z.Off", enabled: false)
        #expect(BenchmarkSides.refusal(.pauseMod(folderName: "Off"), mods: [probe, off],
                                       baseProfileIds: [BenchmarkSides.probeId, "Z.Off"]) == nil)
    }

    @Test func probeVersionFloor() {
        #expect(ProbeLoadRecords.version("0.7.0", atLeast: [0, 7, 0]))
        #expect(ProbeLoadRecords.version("0.10.1", atLeast: [0, 7, 0]))
        #expect(!ProbeLoadRecords.version("0.6.2", atLeast: [0, 7, 0]))
        #expect(!ProbeLoadRecords.version("0.7.0-beta", atLeast: [0, 7, 0]))
        #expect(ProbeLoadRecords.writesLoads(probeVersion: "0.6.0"))
    }
}
