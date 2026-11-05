import Testing
import Foundation
@testable import StarHubTHCore

/// M9 — « Isoler » en piloté charge la ferme du rapport : celle que la
/// sonde a chargée dans la session du côté « après », pas la première venue.
@Suite struct GuidedPilotSaveChoiceTests {
    private func load(_ session: String, kind: ProbeLoadRecord.Kind, save: String?) -> ProbeLoadRecord {
        ProbeLoadRecord(kind: kind, session: session, atText: "", at: nil, probeVersion: "0.9.25",
                        complete: true, reload: false, saveName: save, patchesMeasured: false,
                        saveBytes: nil, saveDate: nil, milestones: [], phases: [], final: nil,
                        health: .init(packSeam: "ok", assetHook: "ok", loadHook: "ok", offThreadSections: 0))
    }

    @Test func picksTheSaveLoadedInTheReportSession() {
        let loads = [load("s1", kind: .save, save: "Ferme_1"), load("s2", kind: .launch, save: nil),
                     load("s2", kind: .save, save: "Ferme_2")]
        #expect(GuidedPilotSaveChoice.save(session: "s2", loads: loads, available: ["Ferme_1", "Ferme_2"]) == "Ferme_2")
    }

    @Test func fallsBackToTheFirstAvailableSave() {
        let loads = [load("s1", kind: .save, save: "Disparue")]
        #expect(GuidedPilotSaveChoice.save(session: "s1", loads: loads, available: ["Ferme_1"]) == "Ferme_1")
        #expect(GuidedPilotSaveChoice.save(session: nil, loads: loads, available: ["Ferme_1"]) == "Ferme_1")
        #expect(GuidedPilotSaveChoice.save(session: "s1", loads: loads, available: []) == nil)
    }

    private func side(_ measurement: ProbeMeasurement, session: String) -> ProbeSide {
        ProbeSide(id: session, kind: .measurement(measurement, crossedChangeAt: nil), session: session,
                  start: nil, end: nil, minutes: [], costs: [], inventory: nil,
                  comparable: ProbeComparableResult(kept: [], exclusions: [:], excluded: []))
    }

    /// X154 — le premier fermier de la liste n'est pas la ferme mesurée.
    @Test func theAfterSideReplaysTheFarmOfTheBeforeSide() {
        let before = ProbeMeasurement(name: "Avant", start: Date(), end: nil)
        let other = ProbeMeasurement(name: "Autre", start: Date(), end: nil)
        let loads = [load("s1", kind: .save, save: "Ferme_1"), load("s2", kind: .save, save: "Ferme_2")]
        let sides = [side(other, session: "s1"), side(before, session: "s2")]
        #expect(GuidedPilotSaveChoice.save(after: before, sides: sides, loads: loads,
                                           available: ["Ferme_1", "Ferme_2"]) == "Ferme_2")
    }

    @Test func anUnknownBeforeSideFallsBackToTheFirstSave() {
        let before = ProbeMeasurement(name: "Avant", start: Date(), end: nil)
        #expect(GuidedPilotSaveChoice.save(after: before, sides: [], loads: [],
                                           available: ["Ferme_1"]) == "Ferme_1")
    }
}
