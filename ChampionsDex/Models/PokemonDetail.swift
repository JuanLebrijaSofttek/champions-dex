import Foundation

struct GenderRatio: Codable {
    let male: Double    // percentage 0–100
    let female: Double
}

struct Ability: Codable {
    let name: String
    let description: String
}

struct Stats: Codable {
    let hp, attack, defense, specialAttack, specialDefense, speed: Int
    var total: Int { hp + attack + defense + specialAttack + specialDefense + speed }
}

struct PokemonForm: Codable {
    let formName: String
    let imageURL: String
    let types: [String]
    let classification: String
    let height: String
    let weight: String
    let abilities: [Ability]
    let stats: Stats
    let typeMatchups: [String: Double]
    let moves: [Move]
}

struct Move: Codable {
    let name: String
    let type: String
    let category: String
    let power: Int?
    let accuracy: Int?
    let pp: Int
    let effect: String
}

struct PokemonDetail: Identifiable, Codable {
    let id: String
    let name: String
    let number: Int
    let genderRatio: GenderRatio?   // nil = genderless
    let forms: [PokemonForm]
    let fetchedAt: Date
}
