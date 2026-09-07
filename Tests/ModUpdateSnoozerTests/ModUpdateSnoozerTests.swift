import Testing
import Foundation
@testable import StarHubTHCore

/// R3 — snooze d'updates Nexus. Un mod snoozé quitte la liste « updates »
/// sans être masqué dans l'inventaire ; l'entrée **expire toute seule**,
/// selon l'un des trois modes. L'identité d'un snooze est l'`UniqueID`
/// du mod — jamais l'identifiant Nexus (58 id partagés sur le parc) ni le
/// nom de dossier (clé des autres magasins, mais un renommage de dossier
/// ne doit pas réveiller un snooze).
@Suite struct ModUpdateSnoozerTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Un suite UserDefaults jetable par test : le store persiste en dehors
    /// de l'instance, aucun test ne doit lire les écritures d'un autre.
    private func freshSnoozer() -> ModUpdateSnoozer {
        let suite = "snoozer-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ModUpdateSnoozer(defaults: defaults)
    }

    // MARK: - Mode une semaine

    @Test func oneWeekHidesTheUpdateUntilItExpires() {
        let snoozer = freshSnoozer()
        snoozer.snooze(uniqueId: "Pathoschild.ChestsAnywhere",
                       mode: .oneWeek,
                       currentModVersion: "2.0.0", currentGameVersion: "1.6.14",
                       now: t0)
        #expect(snoozer.isSnoozed(uniqueId: "Pathoschild.ChestsAnywhere",
                                  currentModVersion: "2.0.0",
                                  currentGameVersion: "1.6.14",
                                  now: t0.addingTimeInterval(6 * 86_400)) == true)
        #expect(snoozer.isSnoozed(uniqueId: "Pathoschild.ChestsAnywhere",
                                  currentModVersion: "2.0.0",
                                  currentGameVersion: "1.6.14",
                                  now: t0.addingTimeInterval(7 * 86_400)) == false)
    }

    // MARK: - Mode jusqu'à prochaine version du mod

    @Test func untilModVersionHoldsWhileTheSameVersionIsAdvertised() {
        let snoozer = freshSnoozer()
        snoozer.snooze(uniqueId: "FlashShifter.StardewValleyExpandedALL",
                       mode: .untilModVersion,
                       currentModVersion: "1.15.0", currentGameVersion: "1.6.14",
                       now: t0)
        // Des mois plus tard, Nexus annonce toujours 1.15.0 : le snooze tient.
        #expect(snoozer.isSnoozed(uniqueId: "FlashShifter.StardewValleyExpandedALL",
                                  currentModVersion: "1.15.0",
                                  currentGameVersion: "1.6.15",
                                  now: t0.addingTimeInterval(90 * 86_400)) == true)
    }

    @Test func untilModVersionExpiresWhenANewVersionAppears() {
        let snoozer = freshSnoozer()
        snoozer.snooze(uniqueId: "FlashShifter.StardewValleyExpandedALL",
                       mode: .untilModVersion,
                       currentModVersion: "1.15.0", currentGameVersion: "1.6.14",
                       now: t0)
        #expect(snoozer.isSnoozed(uniqueId: "FlashShifter.StardewValleyExpandedALL",
                                  currentModVersion: "1.16.0",
                                  currentGameVersion: "1.6.14",
                                  now: t0.addingTimeInterval(86_400)) == false)
    }

    @Test func untilModVersionHoldsWhenNoVersionIsKnown() {
        // Mod absent de la réponse Nexus (429, désinstallé-redisinstallé) :
        // aucune version lue, on ne réveille pas le bruit sur une absence
        // d'information.
        let snoozer = freshSnoozer()
        snoozer.snooze(uniqueId: "some.mod",
                       mode: .untilModVersion,
                       currentModVersion: "1.0.0", currentGameVersion: "1.6.14",
                       now: t0)
        #expect(snoozer.isSnoozed(uniqueId: "some.mod",
                                  currentModVersion: nil,
                                  currentGameVersion: "1.6.14",
                                  now: t0) == true)
    }

    // MARK: - Mode jusqu'à prochaine version de Stardew

    @Test func untilGameVersionExpiresWhenTheLocalGameUpdates() {
        let snoozer = freshSnoozer()
        snoozer.snooze(uniqueId: "some.mod",
                       mode: .untilGameVersion,
                       currentModVersion: "2.0.0", currentGameVersion: "1.6.14",
                       now: t0)
        #expect(snoozer.isSnoozed(uniqueId: "some.mod",
                                  currentModVersion: "2.0.0",
                                  currentGameVersion: "1.6.14",
                                  now: t0.addingTimeInterval(86_400)) == true)
        // Le jeu local est passé en 1.6.15 : le snooze tombe.
        #expect(snoozer.isSnoozed(uniqueId: "some.mod",
                                  currentModVersion: "2.0.0",
                                  currentGameVersion: "1.6.15",
                                  now: t0.addingTimeInterval(86_400)) == false)
    }

    @Test func untilGameVersionHoldsWhenNoGameVersionIsKnown() {
        // Pas de journal SMAPI (nil au snooze comme à la lecture) : rien
        // n'a changé de point de vue observable, le snooze tient.
        let snoozer = freshSnoozer()
        snoozer.snooze(uniqueId: "some.mod",
                       mode: .untilGameVersion,
                       currentModVersion: "2.0.0", currentGameVersion: nil,
                       now: t0)
        #expect(snoozer.isSnoozed(uniqueId: "some.mod",
                                  currentModVersion: "2.0.0",
                                  currentGameVersion: nil,
                                  now: t0) == true)
    }

    // MARK: - Réveil explicite

    @Test func clearingAWakeUpImmediately() {
        let snoozer = freshSnoozer()
        snoozer.snooze(uniqueId: "some.mod",
                       mode: .untilModVersion,
                       currentModVersion: "1.0.0", currentGameVersion: "1.6.14",
                       now: t0)
        snoozer.clear(uniqueId: "some.mod")
        #expect(snoozer.isSnoozed(uniqueId: "some.mod",
                                  currentModVersion: "1.0.0",
                                  currentGameVersion: "1.6.14",
                                  now: t0) == false)
    }

    // MARK: - Persistance et hygiène du store

    @Test func entriesSurviveASnoozerRecreation() {
        let snoozer = freshSnoozer()
        let defaults = snoozer.defaultsForTesting
        snoozer.snooze(uniqueId: "some.mod",
                       mode: .oneWeek,
                       currentModVersion: "1.0.0", currentGameVersion: "1.6.14",
                       now: t0)
        let reluD = ModUpdateSnoozer(defaults: defaults)
        #expect(reluD.isSnoozed(uniqueId: "some.mod",
                                currentModVersion: "1.0.0",
                                currentGameVersion: "1.6.14",
                                now: t0.addingTimeInterval(86_400)) == true)
    }

    @Test func expiredEntriesArePurgedFromTheStore() {
        let snoozer = freshSnoozer()
        snoozer.snooze(uniqueId: "old.mod",
                       mode: .oneWeek,
                       currentModVersion: "1.0.0", currentGameVersion: "1.6.14",
                       now: t0)
        _ = snoozer.isSnoozed(uniqueId: "old.mod",
                              currentModVersion: "1.0.0",
                              currentGameVersion: "1.6.14",
                              now: t0.addingTimeInterval(8 * 86_400))
        #expect(snoozer.entry(for: "old.mod") == nil)
    }

    @Test func corruptedStoreStartsEmptyWithoutCrashing() {
        let suite = "snoozer-tests-corrupt-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("n'est pas du JSON".data(using: .utf8), forKey: ModUpdateSnoozer.storeKey)
        let snoozer = ModUpdateSnoozer(defaults: defaults)
        // Lecture sur store corrompu : vide, pas de crash, et on peut snoozer.
        #expect(snoozer.isSnoozed(uniqueId: "some.mod",
                                  currentModVersion: "1.0.0",
                                  currentGameVersion: "1.6.14",
                                  now: t0) == false)
        snoozer.snooze(uniqueId: "some.mod",
                       mode: .oneWeek,
                       currentModVersion: "1.0.0", currentGameVersion: "1.6.14",
                       now: t0)
        #expect(snoozer.isSnoozed(uniqueId: "some.mod",
                                  currentModVersion: "1.0.0",
                                  currentGameVersion: "1.6.14",
                                  now: t0) == true)
    }

    // MARK: - Introspection pour l'UI

    @Test func entryExposesItsModeAndDeadline() {
        let snoozer = freshSnoozer()
        snoozer.snooze(uniqueId: "some.mod",
                       mode: .oneWeek,
                       currentModVersion: "1.0.0", currentGameVersion: "1.6.14",
                       now: t0)
        let entry = snoozer.entry(for: "some.mod")
        #expect(entry?.mode == .oneWeek)
        #expect(entry?.expiresAt == t0.addingTimeInterval(7 * 86_400))
        // Les modes « jusqu'à version » n'ont pas de date de fin : ils
        // expirent sur un événement, pas sur une horloge.
        snoozer.snooze(uniqueId: "other.mod",
                       mode: .untilModVersion,
                       currentModVersion: "2.0.0", currentGameVersion: "1.6.14",
                       now: t0)
        #expect(snoozer.entry(for: "other.mod")?.expiresAt == nil)
    }
}
