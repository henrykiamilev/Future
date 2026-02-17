import Foundation

protocol SearchServiceProtocol: Sendable {
    func searchUsers(query: String, limit: Int) async throws -> [UserSummary]
    func fetchSuggestedUsers(limit: Int) async throws -> [SuggestedUser]
    func fetchExplorePosts(limit: Int) async throws -> [ExplorePost]
}

final class SearchService: SearchServiceProtocol, Sendable {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func searchUsers(query: String, limit: Int = 20) async throws -> [UserSummary] {
        try await client.request(.searchUsers(query: query, limit: limit))
    }

    func fetchSuggestedUsers(limit: Int = 10) async throws -> [SuggestedUser] {
        try await client.request(.suggestedUsers(limit: limit))
    }

    func fetchExplorePosts(limit: Int = 30) async throws -> [ExplorePost] {
        try await client.request(.explorePosts(limit: limit))
    }
}
