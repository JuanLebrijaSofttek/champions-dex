import Foundation

actor MoveCache {
    private var moves: [String: PokeAPIMoveResponse] = [:]

    func moveResponse(slug: String, service: PokeAPIService) async throws -> PokeAPIMoveResponse {
        if let cached = moves[slug] { return cached }
        let response = try await service.fetchMove(slug: slug)
        moves[slug] = response
        return response
    }
}
