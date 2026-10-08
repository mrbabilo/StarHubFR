import Testing
@testable import StarHubTHCore

/// A5-T6 — un mod qui cite **par son nom** un type interne d'un autre mod
/// (réflexion : `AccessTools.TypeByName`, `Assembly.GetType`…). Règle mesurée
/// sur le parc le 2026-10-08 (ROADMAP) : la chaîne doit être le nom complet
/// d'un `TypeDef` d'**un seul** autre mod.
@Suite struct HiddenCodeDependenciesTests {

    // MARK: - Lecture de la DLL

    @Test func userStringsAreReadInHeapOrder() throws {
        let bytes = HiddenRefsAssembly.bytes
        let root = try #require(DotNetMetadata.metadataRootOffset(inPE: bytes))
        let file = try #require(DotNetMetadata.MetadataFile(bytes: bytes, root: root))
        #expect(file.userStrings() == [
            "ContentPatcher.Framework.PatchManager",
            "SpaceCore.Skills+Skill+Profession, SpaceCore",
            "Pathoschild.Stardew.Automate.Framework.MachineGroup:GetMachines",
            "  FarmTypeManager.ModEntry+Utility:SpawnForage  ",
            "ValleyBonds.IsekaiBonds_RiftEel",
            "ChestsAnywhere.pdb",
            "not a type name",
            "ModEntry",
            "HiddenRefs.Core.Outer+Inner",
            "Généré.Type",
        ])
    }

    /// Le nom d'un type imbriqué suit la réflexion (`Outer+Inner`), à toute
    /// profondeur — c'est la forme que les mods écrivent dans leurs chaînes.
    @Test func typeDefinitionsCarryTheirNestingPath() throws {
        let bytes = HiddenRefsAssembly.bytes
        let root = try #require(DotNetMetadata.metadataRootOffset(inPE: bytes))
        let file = try #require(DotNetMetadata.MetadataFile(bytes: bytes, root: root))
        #expect(file.typeDefFullNames() == [
            "<Module>", "HiddenRefs.Core.Lookups", "HiddenRefs.Core.Outer",
            "HiddenRefs.Core.Outer+Inner", "HiddenRefs.Core.Outer+Inner+Deepest",
        ])
    }

    @Test func anAssemblyKeepsOnlyTypeShapedStrings() throws {
        let assembly = try #require(HiddenCodeDependencies.assembly(uniqueId: "Fixture",
                                                                    bytes: HiddenRefsAssembly.bytes))
        #expect(assembly.citedNames == [
            "ContentPatcher.Framework.PatchManager",
            "SpaceCore.Skills+Skill+Profession",
            "Pathoschild.Stardew.Automate.Framework.MachineGroup",
            "FarmTypeManager.ModEntry+Utility",
            "ValleyBonds.IsekaiBonds_RiftEel",
            "ChestsAnywhere.pdb",
            "HiddenRefs.Core.Outer+Inner",
            "Généré.Type",
        ])
        #expect(assembly.definedTypes.contains("HiddenRefs.Core.Outer+Inner+Deepest"))
    }

    @Test func garbageIsRefusedWithoutCrashing() {
        #expect(HiddenCodeDependencies.assembly(uniqueId: "x", bytes: []) == nil)
        #expect(HiddenCodeDependencies.assembly(uniqueId: "x", bytes: [UInt8](repeating: 0x41, count: 5_000)) == nil)
        _ = HiddenCodeDependencies.assembly(uniqueId: "x", bytes: Array(HiddenRefsAssembly.bytes.prefix(1_500)))
    }

    // MARK: - Rapprochement

    private func asm(_ id: String, defines: Set<String> = [], cites: Set<String> = [])
        -> HiddenCodeDependencies.Assembly {
        .init(uniqueId: id, definedTypes: defines, citedNames: cites)
    }

    @Test func aNameDefinedByOneOtherModIsALink() {
        let links = HiddenCodeDependencies.links([
            asm("Pathoschild.ContentPatcher", defines: ["ContentPatcher.Framework.PatchManager"]),
            asm("Citing", cites: ["ContentPatcher.Framework.PatchManager", "Nobody.Defines.This"]),
        ])
        #expect(links == [.init(citing: "Citing", target: "Pathoschild.ContentPatcher",
                                typeNames: ["ContentPatcher.Framework.PatchManager"])])
    }

    /// Code source partagé (`Pathoschild.Stardew.Common.*`, `SpaceShared.*`) :
    /// compilé dans plusieurs mods, il ne désigne aucun d'eux.
    @Test func aNameDefinedByTwoOtherModsIsSharedCode() {
        let links = HiddenCodeDependencies.links([
            asm("Pathoschild.Automate", defines: ["Pathoschild.Stardew.Common.Utilities.InvariantSet"]),
            asm("Pathoschild.LookupAnything", defines: ["Pathoschild.Stardew.Common.Utilities.InvariantSet"]),
            asm("Citing", cites: ["Pathoschild.Stardew.Common.Utilities.InvariantSet"]),
        ])
        #expect(links.isEmpty)
    }

    /// Le citant qui compile lui-même ce type le lit chez lui.
    @Test func aNameTheCitingModDefinesItselfIsNotALink() {
        let links = HiddenCodeDependencies.links([
            asm("Pathoschild.Automate", defines: ["Pathoschild.Stardew.Common.Utilities.InvariantSet"]),
            asm("Citing", defines: ["Pathoschild.Stardew.Common.Utilities.InvariantSet"],
                cites: ["Pathoschild.Stardew.Common.Utilities.InvariantSet"]),
        ])
        #expect(links.isEmpty)
    }

    /// Un même mod installé deux fois (à plat et dans son dossier de
    /// téléchargement, cas réel de Swim) reste **un** propriétaire.
    @Test func aModInstalledTwiceIsStillOneOwner() {
        let links = HiddenCodeDependencies.links([
            asm("FlyingTNT.Swim", defines: ["Swim.ModEntry"]),
            asm("flyingtnt.swim", defines: ["Swim.ModEntry"]),
            asm("Citing", cites: ["Swim.ModEntry"]),
        ])
        #expect(links.map(\.target) == ["FlyingTNT.Swim"])
    }

    @Test func linksGatherEveryNameAndStayOrdered() {
        let links = HiddenCodeDependencies.links([
            asm("SpaceCore", defines: ["SpaceCore.Skills", "SpaceCore.Skills+Skill"]),
            asm("B", cites: ["SpaceCore.Skills+Skill", "SpaceCore.Skills"]),
            asm("A", cites: ["SpaceCore.Skills"]),
        ])
        #expect(links == [
            .init(citing: "A", target: "SpaceCore", typeNames: ["SpaceCore.Skills"]),
            .init(citing: "B", target: "SpaceCore", typeNames: ["SpaceCore.Skills", "SpaceCore.Skills+Skill"]),
        ])
    }

    /// La fiche ne montre que ce que le manifeste tait (choix du 2026-10-08) :
    /// une dépendance déclarée, requise ou optionnelle, n'apprend rien.
    @Test func undeclaredDropsDeclaredDependenciesIgnoringCase() {
        let links: [HiddenCodeDependencies.Link] = [
            .init(citing: "A", target: "Pathoschild.ContentPatcher", typeNames: ["X.Y"]),
            .init(citing: "A", target: "spacechase0.SpaceCore", typeNames: ["S.T"]),
        ]
        let kept = HiddenCodeDependencies.undeclared(links) { citing in
            citing == "A" ? ["pathoschild.contentpatcher"] : []
        }
        #expect(kept.map(\.target) == ["spacechase0.SpaceCore"])
    }
}
