import Foundation
import Testing
@testable import StarHubTHCore

/// **B6-T3 — santé, endurance et compétences du fermier.**
@Suite struct SaveSkillsTests {
    private let xml = """
        <?xml version="1.0" encoding="utf-8"?><SaveGame xmlns:xsi="x"><player><name>Zofia</name>\
        <health>80</health><maxHealth>100</maxHealth><stamina>269.5</stamina><maxStamina>270</maxStamina>\
        <farmingLevel>2</farmingLevel><fishingLevel>0</fishingLevel><foragingLevel>11</foragingLevel>\
        <miningLevel>0</miningLevel><combatLevel>0</combatLevel><luckLevel>0</luckLevel>\
        <questLog><Quest><monster><health>24</health></monster></Quest></questLog>\
        <experiencePoints><int>400</int><int>0</int><int>20000</int><int>0</int><int>0</int><int>0</int></experiencePoints>\
        <newLevels /></player></SaveGame>
        """

    @Test func levelsFollowTheGameThresholds() {
        #expect(SaveSkills.level(forExperience: 0) == 0)
        #expect(SaveSkills.level(forExperience: 99) == 0)
        #expect(SaveSkills.level(forExperience: 100) == 1)
        #expect(SaveSkills.level(forExperience: 522) == 2)      // pêche, parc
        #expect(SaveSkills.level(forExperience: 8206) == 8)     // combat, parc
        #expect(SaveSkills.level(forExperience: 15000) == 10)
        #expect(SaveSkills.level(forExperience: 99999) == 10)
    }

    @Test func theSaveReadsCurrentStatsAndSkillsOfTheFarmer() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Skills_1", content: xml)

        let save = try #require(SaveManager().parseSaveFile(url: info.fileURL, folderName: "Skills_1"))

        #expect(save.health == 80)          // pas les 24 du monstre de quête
        #expect(save.stamina == 269)
        #expect(save.skills.count == 6)
        #expect(save.skills[0] == SaveSkill(level: 2, experience: 400))
        #expect(save.skills[2] == SaveSkill(level: 11, experience: 20000))
    }

    @Test func raisedExperienceRaisesTheLevelAndQueuesItsProfessions() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Skills_2", content: xml)
        let doc = try SaveDocument(contentsOf: info.fileURL)

        doc.setExperience([800, 0, 20000, 2150, 0, 0])   // agriculture 2 → 3, minage 0 → 5

        let player = try #require(doc.player)
        #expect(player.elements(forName: "farmingLevel").first?.stringValue == "3")
        #expect(player.elements(forName: "miningLevel").first?.stringValue == "5")
        #expect(player.elements(forName: "foragingLevel").first?.stringValue == "11")
        let queued = (player.elements(forName: "newLevels").first?.elements(forName: "Point") ?? []).map {
            ($0.elements(forName: "X").first?.stringValue ?? "", $0.elements(forName: "Y").first?.stringValue ?? "")
        }
        #expect(queued.map(\.0) == ["0", "3", "3", "3", "3", "3"])
        #expect(queued.map(\.1) == ["3", "1", "2", "3", "4", "5"])
    }

    @Test func loweredExperienceLowersTheLevelWithoutQueueingAnything() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Skills_3", content: xml)
        let doc = try SaveDocument(contentsOf: info.fileURL)

        doc.setExperience([50, 0, 20000, 0, 0, 0])

        let player = try #require(doc.player)
        #expect(player.elements(forName: "farmingLevel").first?.stringValue == "0")
        #expect(player.elements(forName: "newLevels").first?.childCount == 0)
    }

    @Test func theDraftWritesOnlyWhatChangedAndClampsCurrentStats() {
        let save = makeTestSave(folderName: "D", fileURL: URL(fileURLWithPath: "/tmp/D"), maxHealth: 100)
        var withStats = save
        withStats.health = 80
        withStats.stamina = 200
        withStats.skills = Array(repeating: SaveSkill(level: 0, experience: 0), count: 6)

        var draft = SaveFarmerDraft(withStats)
        #expect(draft.sheet(for: withStats).health == nil)
        #expect(draft.sheet(for: withStats).experience == nil)

        draft.health = "500"
        draft.experience[3] = "-4"
        draft.experience[0] = "120"
        let sheet = draft.sheet(for: withStats)
        #expect(sheet.health == 100)                 // borné au maximum
        #expect(sheet.experience == [120, 0, 0, 0, 0, 0])
    }

    @Test func theFarmerSheetWritesStatsAndSkillsThroughTheTree() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Skills_4", content: xml)
        let manager = SaveManager(isGameRunning: { false })
        let save = try #require(manager.parseSaveFile(url: info.fileURL, folderName: "Skills_4"))
        var draft = SaveFarmerDraft(save)
        draft.health = "95"
        draft.experience[0] = "1300"

        try manager.writeFarmerSheet(info: save, sheet: draft.sheet(for: save))

        let written = try String(contentsOf: info.fileURL, encoding: .utf8)
        #expect(written.contains("<health>95</health><maxHealth>"))
        #expect(written.contains("<monster><health>24</health></monster>"))
        #expect(written.contains("<farmingLevel>4</farmingLevel>"))
        #expect(written.contains("<experiencePoints><int>1300</int>"))
        #expect(written.contains("<stamina>269.5</stamina>"))   // non saisie : intacte
    }
}
