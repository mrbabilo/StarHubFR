import SwiftUI

/// B6-T3 — santé, endurance et compétences du fermier dans l'éditeur. Le
/// niveau affiché suit les points saisis (seuils du jeu) : c'est celui que
/// l'écriture posera.
struct SaveEditorStatsSections: View {
    @ObservedObject var localization: LocalizationStore
    let save: SaveGameInfo
    @Binding var draft: SaveFarmerDraft

    var body: some View {
        Section(localization.L(L10n.Saves.characterStats)) {
            if save.health != nil {
                TextField(localization.L(L10n.Saves.currentHealth), text: $draft.health)
            }
            TextField(localization.L(L10n.Saves.maxHealth), text: $draft.maxHealth)
            if save.stamina != nil {
                TextField(localization.L(L10n.Saves.currentStamina), text: $draft.stamina)
            }
            TextField(localization.L(L10n.Saves.maxStamina), text: $draft.maxStamina)
        }
        if !save.skills.isEmpty {
            Section {
                ForEach(save.skills.indices, id: \.self) { index in
                    HStack {
                        TextField(localization.L(SaveSkills.nameKeys[index]), text: $draft.experience[index])
                        Text(String(format: localization.L(L10n.Saves.skillLevelFormat), level(at: index)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                }
            } header: {
                Text(localization.L(L10n.Saves.skillsSection))
            } footer: {
                Text(localization.L(L10n.Saves.skillsHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Le niveau qu'aura la compétence : inchangé tant que les points le
    /// sont (une compétence de mod peut dépasser 10).
    private func level(at index: Int) -> Int {
        let skill = save.skills[index]
        guard let points = Int(draft.experience[index].trimmingCharacters(in: .whitespaces)),
              points != skill.experience else { return skill.level }
        let derived = SaveSkills.level(forExperience: max(points, 0))
        return skill.level > 10 && derived == 10 ? skill.level : derived
    }
}
