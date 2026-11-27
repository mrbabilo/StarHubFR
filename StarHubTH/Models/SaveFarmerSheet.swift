import Foundation

/// Ce que l'éditeur écrit sur le fermier (B6-T3). Un champ `nil` est laissé
/// tel quel dans la partie.
struct SaveFarmerSheet: Equatable, Sendable {
    var name: String
    var farmName: String
    var favoriteThing: String
    var money: Int
    var totalMoneyEarned: Int
    var maxHealth: Int
    var maxStamina: Int
    var goldenWalnuts: Int
    var qiGems: Int
    var clubCoins: Int
    var spouse: String
    var health: Int? = nil
    var stamina: Int? = nil
    /// Points des six compétences, ordre de `SaveSkills.levelTags`.
    var experience: [Int]? = nil
}

/// Le formulaire de l'éditeur : du texte saisi, converti au moment d'écrire.
/// Une saisie illisible garde la valeur de la partie.
struct SaveFarmerDraft: Equatable {
    var name: String
    var farmName: String
    var favoriteThing: String
    var spouse: String
    var money: String
    var totalMoneyEarned: String
    var maxHealth: String
    var maxStamina: String
    var goldenWalnuts: String
    var qiGems: String
    var clubCoins: String
    var health: String
    var stamina: String
    var experience: [String]

    init(_ save: SaveGameInfo) {
        name = save.playerName
        farmName = save.farmName
        favoriteThing = save.favoriteThing
        spouse = save.spouse
        money = "\(save.money)"
        totalMoneyEarned = "\(save.totalMoneyEarned)"
        maxHealth = "\(save.maxHealth)"
        maxStamina = "\(save.maxStamina)"
        goldenWalnuts = "\(save.goldenWalnuts)"
        qiGems = "\(save.qiGems)"
        clubCoins = "\(save.clubCoins)"
        health = save.health.map { "\($0)" } ?? ""
        stamina = save.stamina.map { "\($0)" } ?? ""
        experience = save.skills.map { "\($0.experience)" }
    }

    /// La fiche à écrire. Santé et endurance bornées à 0 et au maximum saisi ;
    /// points d'expérience négatifs ramenés à 0. Une valeur inchangée n'est
    /// pas réécrite.
    func sheet(for save: SaveGameInfo) -> SaveFarmerSheet {
        func number(_ text: String, _ fallback: Int) -> Int {
            Int(text.trimmingCharacters(in: .whitespaces)) ?? fallback
        }
        let maxHealthValue = number(maxHealth, save.maxHealth)
        let maxStaminaValue = number(maxStamina, save.maxStamina)
        func current(_ text: String, _ saved: Int?, max: Int) -> Int? {
            guard let saved else { return nil }
            let value = min(Swift.max(number(text, saved), 0), max)
            return value == saved ? nil : value
        }
        let points = zip(experience, save.skills).map { Swift.max(number($0, $1.experience), 0) }
        return SaveFarmerSheet(
            name: name, farmName: farmName, favoriteThing: favoriteThing,
            money: number(money, save.money), totalMoneyEarned: number(totalMoneyEarned, save.totalMoneyEarned),
            maxHealth: maxHealthValue, maxStamina: maxStaminaValue,
            goldenWalnuts: number(goldenWalnuts, save.goldenWalnuts), qiGems: number(qiGems, save.qiGems),
            clubCoins: number(clubCoins, save.clubCoins), spouse: spouse,
            health: current(health, save.health, max: maxHealthValue),
            stamina: current(stamina, save.stamina, max: maxStaminaValue),
            experience: points == save.skills.map(\.experience) || points.isEmpty ? nil : points)
    }
}

extension SaveFarmerDraft {
    /// Champs du formulaire qui diffèrent de `initial` : le compteur du bouton
    /// « Enregistrer », et la garde à la fermeture (audit UX 2026-11-27).
    func changedFields(from initial: SaveFarmerDraft) -> Int {
        zip(fieldValues, initial.fieldValues).filter { $0 != $1 }.count
    }

    private var fieldValues: [String] {
        [name, farmName, favoriteThing, spouse, money, totalMoneyEarned, maxHealth, maxStamina,
         goldenWalnuts, qiGems, clubCoins, health, stamina] + experience
    }
}

extension InventoryItem {
    /// Cases du sac modifiées depuis leur lecture.
    static func changedSlots(_ edited: [InventoryItem], from loaded: [InventoryItem]) -> Int {
        zip(edited, loaded).filter { $0 != $1 }.count
    }
}
