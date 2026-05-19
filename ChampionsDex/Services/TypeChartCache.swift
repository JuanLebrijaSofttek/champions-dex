import Foundation

actor TypeChartCache {
    private var charts: [String: PokeAPITypeResponse] = [:]

    private static let allTypes = ["Normal","Fire","Water","Electric","Grass","Ice",
                                   "Fighting","Poison","Ground","Flying","Psychic","Bug",
                                   "Rock","Ghost","Dragon","Dark","Steel","Fairy"]

    func typeResponse(for typeName: String, service: PokeAPIService) async throws -> PokeAPITypeResponse {
        if let cached = charts[typeName] { return cached }
        let response = try await service.fetchType(typeName: typeName)
        charts[typeName] = response
        return response
    }

    func preloadAll(service: PokeAPIService) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for typeName in Self.allTypes {
                group.addTask { [self] in
                    _ = try await self.typeResponse(for: typeName, service: service)
                }
            }
            try await group.waitForAll()
        }
        print("🗂️✅ [TypeChartCache] preloadAll — \(charts.count) types cached")
    }

    // Computes defensive matchups for a Pokémon's type combo.
    // Fetches lazily if preload was skipped (e.g. offline at launch).
    func computeMatchups(types: [String], service: PokeAPIService) async throws -> [String: Double] {
        var matchups: [String: Double] = Dictionary(
            uniqueKeysWithValues: Self.allTypes.map { ($0, 1.0) }
        )
        for defType in types {
            let response = try await typeResponse(for: defType, service: service)
            for entry in response.damageRelations.doubleDamageFrom { matchups[entry.name.capitalized, default: 1.0] *= 2.0 }
            for entry in response.damageRelations.halfDamageFrom   { matchups[entry.name.capitalized, default: 1.0] *= 0.5 }
            for entry in response.damageRelations.noDamageFrom     { matchups[entry.name.capitalized, default: 1.0] *= 0.0 }
        }
        return matchups.filter { $0.value != 1.0 }
    }
}
