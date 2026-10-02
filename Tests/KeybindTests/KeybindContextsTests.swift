import Testing
import Foundation
@testable import StarHubTHCore

/// Quand deux raccourcis sur la même touche se gênent vraiment (2026-10-03,
/// lecture du code des mods du parc) : touches de modification maintenues,
/// réglages inertes, contextes relevés — et la liste remap par UniqueID.
struct KeybindContextsTests {
    private func tree(_ pairs: [(String, ConfigJSONTree.Value)]) -> ConfigJSONTree.Value {
        .object(ConfigJSONTree.Object(pairs))
    }
    private func mod(_ id: String, _ uid: String = "", _ pairs: [(String, ConfigJSONTree.Value)]) -> KeybindScanner.ModScan {
        .init(id: id, name: id, isActive: true, tree: tree(pairs), uniqueId: uid)
    }

    // MARK: - Touches de modification

    /// Ctrl partagé par trois mods comme touche maintenue : pas de collision,
    /// ni de conflit avec la course (Maj).
    @Test func heldModifiersAreNotCollisions() {
        let r = KeybindScanner.report(mods: [
            mod("a", "", [("ModKey", .string("LeftControl"))]),
            mod("b", "", [("ZoomModifierKey", .string("LeftControl"))]),
            mod("c", "", [("SprintModifier", .string("LeftShift"))]),
        ])
        #expect(r.collisions.isEmpty)
        #expect(r.gameConflicts.isEmpty)
        #expect(r.modifierMods == ["a", "b", "c"])
    }

    /// Alt seul qui **déclenche** (Let's Move It, `ModMenuKey`, `JustPressed`) :
    /// une touche comme une autre — sans nom de modificateur ni relevé, la
    /// collision reste.
    @Test func modifierThatFiresAloneStillCollides() {
        let r = KeybindScanner.report(mods: [
            mod("a", "", [("ModMenuKey", .string("RightAlt"))]),
            mod("b", "", [("OpenKey", .string("RightAlt"))]),
        ])
        #expect(r.collisions.count == 1)
        #expect(r.modifierMods.isEmpty)
    }

    /// Un relevé du code (`held`) suffit quand le nom ne le dit pas.
    @Test func declaredHeldKeyIsSetAside() {
        let held = KeybindContexts(rules: ["x.Tooltips": [.init(keyPaths: ["ShowOneRange"], held: true)]])
        let r = KeybindScanner.report(mods: [
            mod("Tooltips", "x.Tooltips", [("ShowOneRange", .string("LeftControl"))]),
            mod("b", "", [("OpenKey", .string("LeftControl"))]),
        ], contexts: held)
        #expect(r.collisions.isEmpty)
        #expect(r.modifierMods == ["Tooltips"])
    }

    /// Le cas voisin : une combinaison avec modificateur **et** touche reste
    /// une collision.
    @Test func modifierPlusKeyStillCollides() {
        let r = KeybindScanner.report(mods: [
            mod("a", "", [("UseAxeHotkey", .string("LeftControl + D1"))]),
            mod("b", "", [("AbilitySlotKey", .string("LeftControl + D1"))]),
        ])
        #expect(r.collisions.count == 1)
    }

    // MARK: - Remap par UniqueID (régression)

    /// L'app passe le **dossier** en id ; la liste remap porte des UniqueID.
    /// Avant le 2026-10-03, GCSR n'était jamais reconnu dans l'app.
    @Test func remapIsRecognisedByUniqueIdWhenTheIdIsAFolder() {
        let r = KeybindScanner.report(mods: [
            mod("GlobalConfigSettingsRewrite", "FawazT.GlobalConfigSettingsRewrite",
                [("ShiftToolbar", .string("Tab"))]),
        ])
        #expect(r.gameConflicts.isEmpty)
        #expect(r.remapModIDs == ["GlobalConfigSettingsRewrite"])
    }

    // MARK: - Contextes relevés

    private let contexts = KeybindContexts(rules: [
        "moonslime.WizardrySkill": [.init(keyPaths: ["Key_Spell2"], requires: "Key_Cast")],
        "Pathoschild.ChestsAnywhere": [.init(keyPaths: ["Controls.PrevChest"], context: .ownMenu)],
        "BambooKat.Stillbloom": [.init(context: .ownMode)],
        "FawazT.GlobalConfigSettingsRewrite": [.init(keyPaths: ["ShiftToolbar"], context: .world)],
    ])

    /// Sorts de Wizardry : la touche de lancement vaut `None`, le sort sur
    /// 2 ne part jamais — ni collision, ni conflit avec la barre d'outils.
    @Test func inertSettingIsSetAside() {
        let r = KeybindScanner.report(mods: [
            mod("Wizardry", "moonslime.WizardrySkill",
                [("Key_Cast", .string("None")), ("Key_Spell2", .string("D2"))]),
            mod("Chests", "", [("MenuKey", .string("D2"))]),
        ], contexts: contexts)
        #expect(r.collisions.isEmpty)
        #expect(r.inertMods == ["Wizardry"])
        // Le voisin non inerte reste en conflit avec l'emplacement 2.
        #expect(!r.gameConflicts.isEmpty)
    }

    /// La même touche de lancement assignée : le sort redevient actif.
    @Test func assignedActivationKeyMakesItLiveAgain() {
        let r = KeybindScanner.report(mods: [
            mod("Wizardry", "moonslime.WizardrySkill",
                [("Key_Cast", .string("Q")), ("Key_Spell2", .string("D2"))]),
            mod("Chests", "", [("MenuKey", .string("D2"))]),
        ], contexts: contexts)
        #expect(r.collisions.count == 1)
        #expect(r.inertMods.isEmpty)
    }

    /// Un réglage lu seulement dans son propre menu ne croise pas un réglage
    /// sans garde… sauf si l'autre agit partout : là, ils se croisent.
    @Test func ownMenuOverlapsOnlyAnywhere() {
        #expect(!KeybindContexts.Context.ownMenu.overlaps(.world))
        #expect(KeybindContexts.Context.ownMenu.overlaps(.anywhere))
        #expect(!KeybindContexts.Context.eventReplay.overlaps(.worldNoEvent))
    }

    /// Dans un menu, le jeu écoute encore ses contrôles de menu (Échap, E) :
    /// un menu propre n'est exempté que des contrôles de jeu en monde.
    @Test func ownMenuStillReachesMenuControls() {
        #expect(KeybindContexts.Context.ownMenu.reaches("menuButton"))
        #expect(!KeybindContexts.Context.ownMenu.reaches("inventorySlot2"))
        #expect(!KeybindContexts.Context.ownMode.reaches("menuButton"))
        let r = KeybindScanner.report(mods: [
            mod("Chests", "Pathoschild.ChestsAnywhere", [("Controls.PrevChest", .string("Escape"))]),
        ], contexts: contexts)
        #expect(r.gameConflicts.map(\.control.name) == ["menuButton"])
    }

    /// Un mod inconnu de la table vaut `anywhere` : le conflit reste.
    @Test func unknownModsKeepTheirConflict() {
        let r = KeybindScanner.report(mods: [
            mod("Chests", "Pathoschild.ChestsAnywhere", [("Controls.PrevChest", .string("LeftShoulder"))]),
            mod("Other", "", [("Hotkey", .string("LeftShoulder"))]),
        ], contexts: contexts)
        #expect(r.gamepadCollisions.count == 1)
    }

    /// Deux mods à contexte propre ne se croisent pas : collision levée et
    /// nommée.
    @Test func twoOwnContextsDoNotCollide() {
        let r = KeybindScanner.report(mods: [
            mod("Chests", "Pathoschild.ChestsAnywhere", [("Controls.PrevChest", .string("LeftShoulder"))]),
            mod("Stillbloom", "BambooKat.Stillbloom", [("GrabKey", .string("LeftShoulder"))]),
        ], contexts: contexts)
        #expect(r.gamepadCollisions.isEmpty)
        #expect(r.contextResolvedMods == ["Chests", "Stillbloom"])
    }

    /// Mode propre (Stillbloom) : W ne touche pas le contrôle « haut » du jeu.
    @Test func ownModeDoesNotReachGameControls() {
        let r = KeybindScanner.report(mods: [
            mod("Stillbloom", "BambooKat.Stillbloom", [("CameraUpKey", .string("W"))]),
        ], contexts: contexts)
        #expect(r.gameConflicts.isEmpty)
    }

    /// Une touche de remap (contrôle du jeu) ne croise pas le menu propre
    /// d'un autre mod : Tab de GCSR contre l'aperçu de Chests Anywhere.
    @Test func remapKeyDoesNotCrossAnOwnMenu() {
        let r = KeybindScanner.report(mods: [
            mod("GlobalConfigSettingsRewrite", "FawazT.GlobalConfigSettingsRewrite",
                [("ShiftToolbar", .string("Tab"))]),
            mod("Chests", "Pathoschild.ChestsAnywhere", [("Controls.PrevChest", .string("Tab"))]),
        ], contexts: contexts)
        #expect(r.collisions.isEmpty)
    }

    /// Le fichier livré se lit.
    @Test func bundledFileDecodes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("assets/keybind-contexts.json")
        let contexts = try KeybindContexts(data: Data(contentsOf: url))
        #expect(contexts.context(uniqueId: "BambooKat.Stillbloom", keyPath: ["SaveKey"]) == .ownMode)
    }

    // MARK: - L'éditeur décide comme le rapport

    /// Stillbloom, mode éditeur : W n'est pas annoncé « lié à » moveUp.
    @Test func annotationHonoursOwnMode() {
        let r = KeybindScanner.report(mods: [
            mod("Stillbloom", "BambooKat.Stillbloom", [("CameraUpKey", .string("W"))]),
        ], contexts: contexts)
        let note = KeybindScanner.annotation(for: KeybindCombo(buttons: ["W"])!, ofMod: "Stillbloom",
                                             keyPath: ["CameraUpKey"], in: r)
        #expect(note.isEmpty)
    }

    /// Une touche de modification seule, même capturée à l'instant : muette.
    @Test func annotationIgnoresHeldModifiers() {
        let r = KeybindScanner.report(mods: [mod("a", "", [("ModKey", .string("LeftShift"))])])
        let note = KeybindScanner.annotation(for: KeybindCombo(buttons: ["LeftShift"])!, ofMod: "a",
                                             keyPath: ["ModKey"], in: r)
        #expect(note.isEmpty)
    }

    /// Le réglage inerte de Wizardry ne s'annonce pas sur l'emplacement 2.
    @Test func annotationIgnoresInertSettings() {
        let r = KeybindScanner.report(mods: [
            mod("Wizardry", "moonslime.WizardrySkill",
                [("Key_Cast", .string("None")), ("Key_Spell2", .string("D2"))]),
        ], contexts: contexts)
        let note = KeybindScanner.annotation(for: KeybindCombo(buttons: ["D2"])!, ofMod: "Wizardry",
                                             keyPath: ["Key_Spell2"], in: r)
        #expect(note.isEmpty)
    }

    /// L'id du dossier : la rangée ne se signale pas en conflit avec
    /// elle-même (l'éditeur passait l'UniqueID, jamais égal au dossier).
    @Test func annotationDoesNotListTheRowItself() {
        let r = KeybindScanner.report(mods: [mod("Folder", "Author.Mod", [("Key", .string("K"))])])
        let note = KeybindScanner.annotation(for: KeybindCombo(buttons: ["K"])!, ofMod: "Folder",
                                             keyPath: ["Key"], in: r)
        #expect(note.conflicts.isEmpty)
    }
}
