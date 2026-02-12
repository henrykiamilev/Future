import Foundation

protocol SearchServiceProtocol: Sendable {
    func searchUsers(query: String, limit: Int) async throws -> [UserSummary]
}

final class SearchService: SearchServiceProtocol, Sendable {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func searchUsers(query: String, limit: Int = 20) async throws -> [UserSummary] {
        try await client.request(.searchUsers(query: query, limit: limit))
    }
}
