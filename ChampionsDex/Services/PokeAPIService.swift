import Foundation

// MARK: - Error

enum PokeAPIError: Error {
    case httpError(Int)
    case missingEnglishEntry(String)
    case noFormsAvailable
    case typeMissing(String)
}

// MARK: - Response structs (decode only the fields we use; Decodable ignores the rest)

struct PokeAPIPokemonResponse: Decodable {
    struct TypeEntry: Decodable {
        struct TypeName: Decodable { let name: String }
        let slot: Int
        let type: TypeName
    }
    struct StatEntry: Decodable {
        struct StatName: Decodable { let name: String }
        let baseStat: Int
        let stat: StatName
    }
    struct AbilityEntry: Decodable {
        struct AbilityName: Decodable { let name: String }
        let ability: AbilityName
    }
    struct FormEntry: Decodable { let name: String }
    struct Sprites: Decodable {
        struct Other: Decodable {
            struct Home: Decodable { let frontDefault: String? }
            let home: Home?
        }
        let frontDefault: String?
        let other: Other?
    }
    let id: Int
    let name: String
    let height: Int
    let weight: Int
    let types: [TypeEntry]
    let stats: [StatEntry]
    let abilities: [AbilityEntry]
    let forms: [FormEntry]
    let sprites: Sprites
}

struct PokeAPISpeciesResponse: Decodable {
    struct GenusEntry: Decodable {
        struct Language: Decodable { let name: String }
        let genus: String
        let language: Language
    }
    struct Variety: Decodable {
        struct PokemonRef: Decodable { let name: String }
        let isDefault: Bool
        let pokemon: PokemonRef
    }
    let genderRate: Int
    let genera: [GenusEntry]
    let varieties: [Variety]
}

struct PokeAPIAbilityResponse: Decodable {
    struct EffectEntry: Decodable {
        struct Language: Decodable { let name: String }
        let shortEffect: String
        let language: Language
    }
    let name: String
    let effectEntries: [EffectEntry]
}

struct PokeAPIFormResponse: Decodable {
    struct TypeEntry: Decodable {
        struct TypeName: Decodable { let name: String }
        let slot: Int
        let type: TypeName
    }
    struct Sprites: Decodable { let frontDefault: String? }
    let name: String
    let formName: String
    let types: [TypeEntry]
    let sprites: Sprites
}

struct PokeAPITypeResponse: Decodable {
    struct TypeEntry: Decodable { let name: String }
    struct DamageRelations: Decodable {
        let doubleDamageFrom: [TypeEntry]
        let halfDamageFrom: [TypeEntry]
        let noDamageFrom: [TypeEntry]
    }
    let name: String
    let damageRelations: DamageRelations
}

struct PokeAPIMoveResponse: Decodable {
    struct TypeName: Decodable { let name: String }
    struct DamageClass: Decodable { let name: String }
    struct EffectEntry: Decodable {
        struct Language: Decodable { let name: String }
        let shortEffect: String
        let language: Language
    }
    let name: String
    let type: TypeName
    let damageClass: DamageClass
    let power: Int?
    let accuracy: Int?
    let pp: Int
    let effectEntries: [EffectEntry]
}

// MARK: - Service

struct PokeAPIService {
    private static let base = "https://pokeapi.co/api/v2"

    // Variety slug suffixes excluded from Champions — not available in-game.
    // -gmax: Gigantamax (Sword/Shield mechanic)
    // -mega-z: Z-powered Mega (Champions mechanic not yet implemented)
    private static let excludedVarietySuffixes: [String] = ["-gmax", "-mega-z"]

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: Public fetch methods

    func fetchPokemon(slug: String) async throws -> PokeAPIPokemonResponse {
        try await fetch("/pokemon/\(slug)")
    }

    func fetchSpecies(slug: String) async throws -> PokeAPISpeciesResponse {
        try await fetch("/pokemon-species/\(slug)")
    }

    func fetchAbility(slug: String) async throws -> PokeAPIAbilityResponse {
        try await fetch("/ability/\(slug)")
    }

    func fetchForm(slug: String) async throws -> PokeAPIFormResponse {
        try await fetch("/pokemon-form/\(slug)")
    }

    func fetchType(typeName: String) async throws -> PokeAPITypeResponse {
        try await fetch("/type/\(typeName.lowercased())")
    }

    func fetchMove(slug: String) async throws -> PokeAPIMoveResponse {
        try await fetch("/move/\(slug)")
    }

    // MARK: Detail assembly

    func fetchDetail(
        slug: String,
        formData: SerebiiService.SerebiiFormData,
        typeChartCache: TypeChartCache,
        moveCache: MoveCache,
        progress: @escaping (String, Double) -> Void
    ) async throws -> PokemonDetail {

        progress("Fetching Pokémon data...", 0.0)

        // Species first — its `varieties` field gives the real pokemon slugs for every form.
        // Megas and regionals are varieties, not `forms` on the base pokemon endpoint.
        // The plain `/pokemon/{slug}` also sometimes 404s when the species has only
        // gender-split varieties (e.g. basculegion → basculegion-m / basculegion-f).
        // Normalize the Serebii slug to a PokéAPI-compatible slug (e.g. mr.rime → mr-rime).
        let apiSlug = Self.toPokeAPISlug(slug)
        let s = try await fetchSpecies(slug: apiSlug)

        // Put the default variety first, then non-defaults in API order.
        // Exclude Gigantamax varieties — that's a Sword/Shield mechanic not in Champions.
        let defaultVariety    = s.varieties.first(where: { $0.isDefault })
        let nonDefaults       = s.varieties.filter { v in !v.isDefault && !Self.excludedVarietySuffixes.contains { v.pokemon.name.hasSuffix($0) } }
        let orderedVarieties  = (defaultVariety.map { [$0] } ?? []) + nonDefaults

        // Serebii's stat-table count is the primary form signal, but some Pokémon (e.g. Rotom)
        // consolidate shared-stat forms into one table on the Champions page.
        // When PokéAPI lists only a few more varieties than Serebii detected (gap ≤ 4),
        // trust PokéAPI — the extra varieties represent distinct in-game forms.
        // A larger gap (e.g. Pikachu's 14 cap variants vs 1 stat table) means cosmetic-only
        // PokéAPI entries that Serebii correctly omits.
        let pokeAPIVarietyCount = orderedVarieties.count
        let effectiveFormCount  = (pokeAPIVarietyCount - formData.formCount <= 4)
            ? pokeAPIVarietyCount : formData.formCount
        let usedVarieties = Array(orderedVarieties.prefix(effectiveFormCount))
        let varietySlugs  = usedVarieties.map { $0.pokemon.name }
        print("🌐✅ [PokeAPI] fetchDetail(\(slug)) — \(varietySlugs.count) variety slug(s): \(varietySlugs)")

        progress("Fetching abilities & forms...", 0.20)

        // Fetch every variety as a full /pokemon/ entry (gives per-form stats, types, sprite).
        let varietyPokemons = try await fetchAllPokemons(slugs: varietySlugs)

        // Fetch abilities per form in parallel with move details.
        // Mega forms have their own unique abilities (e.g. Mega Charizard X → Tough Claws).
        async let abilitiesPerFormTask = fetchAbilitiesPerForm(varietyPokemons: varietyPokemons)

        progress("Fetching move details...", 0.50)

        let allDisplayNames = formData.movesByForm.flatMap { $0 }
        var displayNameForSlug: [String: String] = [:]
        for name in allDisplayNames { displayNameForSlug[Self.toMoveSlug(name)] = name }
        let uniqueSlugs = Array(Set(allDisplayNames.map { Self.toMoveSlug($0) }))
        async let moveDictTask = fetchMoves(slugs: uniqueSlugs, displayNames: displayNameForSlug, cache: moveCache)

        let (abilitiesPerForm, moveDict) = try await (abilitiesPerFormTask, moveDictTask)

        progress("Computing type matchups...", 0.80)

        let baseName       = slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        let genderRatioVal = Self.genderRatio(from: s.genderRate)
        let classification = s.genera.first(where: { $0.language.name == "en" })?.genus ?? ""

        // Separate primary move tables (≥ half the size of the largest table, minimum 8)
        // from supplemental tables. Supplemental tables hold form-specific signature moves
        // (e.g. Rotom's 5-entry table: Overheat, Hydro Pump, Air Slash, Blizzard, Leaf Storm)
        // that are appended one-per-non-base-form rather than replacing the shared pool.
        let primaryMoveCount  = formData.movesByForm.map(\.count).max() ?? 0
        let minTableSize      = max(8, primaryMoveCount / 2)
        let perFormTables     = formData.movesByForm.filter { $0.count >= minTableSize }
        let supplementalMoves = formData.movesByForm.filter { $0.count < minTableSize }.flatMap { $0 }

        var forms: [PokemonForm] = []
        for i in 0..<varietyPokemons.count {
            let vp = varietyPokemons[i]
            let types  = vp.types.sorted { $0.slot < $1.slot }.map { $0.type.name.capitalized }
            let sprite = vp.sprites.other?.home?.frontDefault ?? vp.sprites.frontDefault ?? ""
            let formName = i == 0 ? baseName
                                  : Self.formDisplayName(varietySlug: varietySlugs[i], baseSlug: slug, baseName: baseName)
            let matchups = try await typeChartCache.computeMatchups(types: types, service: self)
            // Shared move pool, with per-form signature move appended for non-base forms.
            let sharedMoves = i < perFormTables.count ? perFormTables[i] : (perFormTables.first ?? [])
            let signature   = (i > 0 && i - 1 < supplementalMoves.count) ? [supplementalMoves[i - 1]] : []
            let rawMoves    = sharedMoves + signature
            let moves    = rawMoves.compactMap { moveDict[Self.toMoveSlug($0)] }

            let abilities = i < abilitiesPerForm.count ? abilitiesPerForm[i] : (abilitiesPerForm.first ?? [])
            forms.append(PokemonForm(
                formName:       formName,
                imageURL:       sprite,
                types:          types,
                classification: classification,
                height:         Self.formatHeight(vp.height),
                weight:         Self.formatWeight(vp.weight),
                abilities:      abilities,
                stats:          Self.buildStats(from: vp.stats),
                typeMatchups:   matchups,
                moves:          moves
            ))
        }

        progress("Saving...", 0.95)
        print("🌐✅ [PokeAPI] fetchDetail(\(slug)) — \(forms.count) form(s) built")
        return PokemonDetail(
            id: slug, name: baseName, number: varietyPokemons[0].id,
            genderRatio: genderRatioVal, forms: forms, fetchedAt: Date()
        )
    }

    // MARK: Private helpers

    private func fetchAbilities(slugs: [String]) async throws -> [Ability] {
        var resolved: [Ability] = []
        try await withThrowingTaskGroup(of: (Int, Ability).self) { group in
            for (i, slug) in slugs.enumerated() {
                group.addTask {
                    let r = try await self.fetchAbility(slug: slug)
                    let desc = r.effectEntries.first(where: { $0.language.name == "en" })?.shortEffect ?? ""
                    return (i, Ability(name: r.name.capitalized.replacingOccurrences(of: "-", with: " "), description: desc))
                }
            }
            var indexed: [(Int, Ability)] = []
            for try await pair in group { indexed.append(pair) }
            resolved = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        return resolved
    }

    private func fetchAbilitiesPerForm(varietyPokemons: [PokeAPIPokemonResponse]) async throws -> [[Ability]] {
        var result: [[Ability]] = []
        try await withThrowingTaskGroup(of: (Int, [Ability]).self) { group in
            for (i, vp) in varietyPokemons.enumerated() {
                let slugs = vp.abilities.map { $0.ability.name }
                group.addTask { (i, try await self.fetchAbilities(slugs: slugs)) }
            }
            var indexed: [(Int, [Ability])] = []
            for try await pair in group { indexed.append(pair) }
            result = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        return result
    }

    private func fetchAllPokemons(slugs: [String]) async throws -> [PokeAPIPokemonResponse] {
        var resolved: [PokeAPIPokemonResponse] = []
        try await withThrowingTaskGroup(of: (Int, PokeAPIPokemonResponse).self) { group in
            for (i, slug) in slugs.enumerated() {
                group.addTask { (i, try await self.fetchPokemon(slug: slug)) }
            }
            var indexed: [(Int, PokeAPIPokemonResponse)] = []
            for try await pair in group { indexed.append(pair) }
            resolved = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        return resolved
    }

    private func fetchMoves(
        slugs: [String],
        displayNames: [String: String],
        cache: MoveCache
    ) async throws -> [String: Move] {
        var result: [String: Move] = [:]
        try await withThrowingTaskGroup(of: (String, Move?).self) { group in
            for slug in slugs {
                group.addTask {
                    do {
                        let r    = try await cache.moveResponse(slug: slug, service: self)
                        let name = displayNames[slug] ?? r.name.capitalized
                        let desc = r.effectEntries.first(where: { $0.language.name == "en" })?.shortEffect ?? ""
                        let move = Move(
                            name:     name,
                            type:     r.type.name.capitalized,
                            category: r.damageClass.name.capitalized,
                            power:    r.power,
                            accuracy: r.accuracy,
                            pp:       r.pp,
                            effect:   desc
                        )
                        return (slug, move)
                    } catch {
                        print("🌐❌ [PokeAPI] fetchMove(\(slug)) — \(error) (skipping)")
                        return (slug, nil)
                    }
                }
            }
            for try await (slug, move) in group {
                if let move { result[slug] = move }
            }
        }
        return result
    }

    // Converts a Serebii URL slug to a PokéAPI-compatible slug.
    // Serebii uses periods for Mr. Mime / Mr. Rime; PokéAPI uses hyphens.
    private static func toPokeAPISlug(_ slug: String) -> String {
        slug.replacingOccurrences(of: ".", with: "-")
    }

    private static func toMoveSlug(_ displayName: String) -> String {
        displayName
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "-")
    }

    // Derives a display name for an alternate form from the variety slug.
    // e.g. "charizard-mega-x" + base "charizard" → suffix "mega-x" → "Mega X Charizard"
    private static func formDisplayName(varietySlug: String, baseSlug: String, baseName: String) -> String {
        let suffix: String
        if varietySlug == baseSlug {
            suffix = ""
        } else {
            let prefix = baseSlug + "-"
            suffix = varietySlug.hasPrefix(prefix) ? String(varietySlug.dropFirst(prefix.count)) : varietySlug
        }
        guard !suffix.isEmpty else { return baseName }

        let prefixMap: [String: String] = [
            "mega":     "Mega",       "mega-x":   "Mega X",   "mega-y":  "Mega Y",
            "gmax":     "Gigantamax",
            "alola":    "Alolan",     "galar":    "Galarian", "hisui":   "Hisuian",
            "paldea":   "Paldean",    "original": "Original",
            "m":        "Male",       "f":        "Female",
            "male":     "Male",       "female":   "Female",
        ]
        let label = prefixMap[suffix] ?? suffix.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        return "\(label) \(baseName)"
    }

    private static func formatHeight(_ decimeters: Int) -> String {
        String(format: "%.1f m", Double(decimeters) / 10.0)
    }

    private static func formatWeight(_ hectograms: Int) -> String {
        String(format: "%.1f kg", Double(hectograms) / 10.0)
    }

    private static func genderRatio(from genderRate: Int) -> GenderRatio? {
        guard genderRate >= 0 else { return nil }
        let femalePct = Double(genderRate) / 8.0 * 100.0
        return GenderRatio(male: 100.0 - femalePct, female: femalePct)
    }

    private static func buildStats(from entries: [PokeAPIPokemonResponse.StatEntry]) -> Stats {
        var hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0
        for e in entries {
            switch e.stat.name {
            case "hp":               hp  = e.baseStat
            case "attack":           atk = e.baseStat
            case "defense":          def = e.baseStat
            case "special-attack":   spa = e.baseStat
            case "special-defense":  spd = e.baseStat
            case "speed":            spe = e.baseStat
            default: break
            }
        }
        return Stats(hp: hp, attack: atk, defense: def, specialAttack: spa, specialDefense: spd, speed: spe)
    }

    // MARK: Network helper

    private func fetch<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(Self.base)\(path)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("🌐\(status == 200 ? "✅" : "❌") [PokeAPI] GET \(path) — HTTP \(status) \(data.count)B")
        guard status == 200 else { throw PokeAPIError.httpError(status) }
        return try Self.decoder.decode(T.self, from: data)
    }
}
