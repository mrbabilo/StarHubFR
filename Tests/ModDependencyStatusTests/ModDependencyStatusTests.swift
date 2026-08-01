import Testing
@testable import StarHubTHCore

/// Ces deux calculs commandent le filtre « Problèmes » et les avertissements de
/// la fiche mod. Un faux positif y envoie chercher une panne qui n'existe pas ;
/// un oubli laisse un mod muet alors qu'il ne tournera pas.
struct ModDependencyStatusTests {
    private func mod(requiring required: [String], optional: [String] = []) -> ModItem {
        ModItem(uniqueId: "id.mod", name: "M", folderName: "M", version: "1", author: "",
                description: "", nexusUrl: "", nexusModId: "", isEnabled: true,
                dependencies: required.map { ModDependency(uniqueId: $0, isRequired: true) }
                    + optional.map { ModDependency(uniqueId: $0, isRequired: false) })
    }

    @Test func aRequiredDependencyNobodyProvidesIsMissing() {
        #expect(ModDependencyStatus.missing(for: mod(requiring: ["Pathoschild.ContentPatcher"]),
                                            installedIds: []) == ["Pathoschild.ContentPatcher"])
    }

    @Test func anInstalledDependencyIsNotMissing() {
        #expect(ModDependencyStatus.missing(for: mod(requiring: ["A"]),
                                            installedIds: ["a"]).isEmpty)
    }

    @Test func identifiersMatchWithoutRegardToCase() {
        // SMAPI compare sans égard à la casse ; deux auteurs écrivent rarement
        // le même identifiant de la même façon.
        #expect(ModDependencyStatus.missing(for: mod(requiring: ["Pathoschild.ContentPatcher"]),
                                            installedIds: ["pathoschild.contentpatcher"]).isEmpty)
    }

    @Test func anOptionalDependencyIsNeverReported() {
        #expect(ModDependencyStatus.missing(for: mod(requiring: [], optional: ["Absent"]),
                                            installedIds: []).isEmpty)
        #expect(ModDependencyStatus.disabled(for: mod(requiring: [], optional: ["A"]),
                                             states: ["a": false]).isEmpty)
    }

    @Test func anInstalledButPausedDependencyIsReported() {
        #expect(ModDependencyStatus.disabled(for: mod(requiring: ["A"]),
                                             states: ["a": false]) == ["A"])
    }

    @Test func anEnabledDependencyIsNotReported() {
        #expect(ModDependencyStatus.disabled(for: mod(requiring: ["A"]),
                                             states: ["a": true]).isEmpty)
    }

    @Test func anAbsentDependencyIsNotCountedAsPaused() {
        // Elle relève de `missing`, pas de `disabled` : la compter deux fois
        // ferait afficher deux problèmes pour un seul.
        #expect(ModDependencyStatus.disabled(for: mod(requiring: ["A"]), states: [:]).isEmpty)
    }

    @Test func aModWithNoDependenciesHasNoProblem() {
        #expect(ModDependencyStatus.missing(for: mod(requiring: []), installedIds: []).isEmpty)
    }
}
