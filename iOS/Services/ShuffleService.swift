import Foundation

protocol ShuffleServiceProtocol: Sendable {
    func fetchDeck(limit: Int) async throws -> ShuffleDeckResponse
    func recordAction(targetUserID: UUID, action: String) async throws
    func fetchSavedUsers(limit: Int) async throws -> [SuggestedUser]
    func unsaveUser(userID: UUID) async throws
}

final class ShuffleService: ShuffleServiceProtocol, Sendable {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func fetchDeck(limit: Int = 20) async throws -> ShuffleDeckResponse {
        try await client.request(.shuffleDeck(limit: limit))
    }

    func recordAction(targetUserID: UUID, action: String) async throws {
        try await client.requestVoid(.recordShuffleAction(targetUserID: targetUserID, action: action))
    }

    func fetchSavedUsers(limit: Int = 50) async throws -> [SuggestedUser] {
        try await client.request(.savedUsers(limit: limit))
    }

    func unsaveUser(userID: UUID) async throws {
        try await client.requestVoid(.unsaveUser(userID: userID))
    }
}
