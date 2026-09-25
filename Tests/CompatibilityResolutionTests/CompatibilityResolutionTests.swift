import Testing
@testable import StarHubTHCore

/// Les neuf mods que smapi.io signalait sur le parc de l'auteur le
/// 2026-09-25 : sept déjà réglés, deux toujours à signaler.
@Suite("Verdict smapi.io déjà réglé par la version installée")
struct CompatibilityResolutionTests {
    private func verdict(_ status: ModCompatibility.Status, _ summary: String,
                         links: [(String, String)] = []) -> ModCompatibility {
        ModCompatibility(status: status, brokeIn: "Stardew Valley 1.6", summary: summary,
                         links: links.map { ModCompatibility.Link(label: $0.0, url: $0.1) })
    }
    private let forum = "https://forums.stardewvalley.net/threads/unofficial-mod-updates.2096/p"

    @Test func laVersionRecommandeeEstInstallee() {
        let v = verdict(.unofficial, "broken, use unofficial version (1.1.3-unofficial.1-p1xel8ted).",
                        links: [("unofficial version", forum)])
        #expect(CompatibilityResolution.resolution(of: v, installedVersion: "1.1.3-unofficial.1-p1xel8ted",
                                                   installedNexusId: "")
                == .recommendedVersionInstalled("1.1.3-unofficial.1-p1xel8ted"))
    }

    /// BusLocations 2.1.1 et ModUpdateMenu 2.7.0 : plus récents que la
    /// version non officielle proposée.
    @Test func uneVersionPlusRecenteRegleAussi() {
        let bus = verdict(.unofficial, "broken, use unofficial version (1.2.2-unofficial.1-Xytronix).")
        #expect(CompatibilityResolution.resolution(of: bus, installedVersion: "2.1.1", installedNexusId: "") != nil)
        let menu = verdict(.unofficial, "broken, use unofficial version (1.6.1-unofficial-2.dphill).")
        #expect(CompatibilityResolution.resolution(of: menu, installedVersion: "2.7.0", installedNexusId: "") != nil)
    }

    /// Adventurer's Guild Expanded, Train Tracks, Informant : le lien Nexus
    /// proposé est la page du mod installé.
    @Test func leRemplacantProposeEstInstalle() {
        let age = verdict(.unofficial, "use unofficial update or Adventurer's Guild Expanded - Unofficial Update for 1.6.",
                          links: [("unofficial update", forum),
                                  ("AGE", "https://www.nexusmods.com/stardewvalley/mods/22591")])
        #expect(CompatibilityResolution.resolution(of: age, installedVersion: "2.3.2", installedNexusId: "22591")
                == .replacementInstalled(nexusId: "22591"))
        let tracks = verdict(.workaround, "use Train Tracks - Continued instead.",
                             links: [("Train Tracks - Continued", "https://www.nexusmods.com/stardewvalley/mods/28049")])
        #expect(CompatibilityResolution.resolution(of: tracks, installedVersion: "1.0.5", installedNexusId: "28049") != nil)
    }

    /// PersonalEffects (bêta, aucun lien) et LovedLabels : toujours signalés.
    @Test func sansVersionNiRemplacantLeVerdictReste() {
        let broken = verdict(.broken, "broken, not updated yet.")
        #expect(CompatibilityResolution.resolution(of: broken, installedVersion: "1.6.7-beta.1", installedNexusId: "8616") == nil)
        #expect(CompatibilityResolution.resolution(of: broken, installedVersion: "2.1.0", installedNexusId: "") == nil)
    }

    /// Le cas voisin qui ne doit PAS se régler : une version plus ancienne
    /// que la recommandée, ou un autre mod que le remplaçant.
    @Test func uneVersionPlusAncienneOuUnAutreModResteSignale() {
        let v = verdict(.unofficial, "broken, use unofficial version (1.1.3-unofficial.1-p1xel8ted).",
                        links: [("x", "https://www.nexusmods.com/stardewvalley/mods/22591")])
        #expect(CompatibilityResolution.resolution(of: v, installedVersion: "1.1.2", installedNexusId: "999") == nil)
        #expect(CompatibilityResolution.resolution(of: v, installedVersion: "1.1.3", installedNexusId: "") != nil)
        #expect(CompatibilityResolution.resolution(of: v, installedVersion: "1.1.3-beta", installedNexusId: "") == nil)
    }
}
