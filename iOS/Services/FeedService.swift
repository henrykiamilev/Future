import Foundation

protocol FeedServiceProtocol: Sendable {
    func fetchMainFeed(cursor: FeedCursor?, limit: Int) async throws -> FeedPage
    func fetchFriendsFeed(cursor: FeedCursor?, limit: Int) async throws -> FeedPage
    func fetchDiscovery(limit: Int) async throws -> FeedPage
    func recordExposures(authorIDs: [UUID]) async throws
    func recordConsumption(postID: UUID, feedType: String) async throws
}

final class FeedService: FeedServiceProtocol, Sendable {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func fetchMainFeed(cursor: FeedCursor? = nil, limit: Int = 20) async throws -> FeedPage {
        var cursorScore: Double?
        var cursorID: UUID?

        if case .ranked(let score, let id) = cursor {
            cursorScore = score
            cursorID = id
        }

        let page: FeedPage = try await client.request(
            .mainFeed(cursorScore: cursorScore, cursorID: cursorID, limit: limit)
        )

        // Exposure tracking is now handled atomically inside get_main_feed() on the server.
        // No separate client-side call needed.

        return page
    }

    /// v2: Friends feed now uses ranked cursor (score, id) instead of chronological
    func fetchFriendsFeed(cursor: FeedCursor? = nil, limit: Int = 20) async throws -> FeedPage {
        var cursorScore: Double?
        var cursorID: UUID?

        if case .ranked(let score, let id) = cursor {
            cursorScore = score
            cursorID = id
        }

        return try await client.request(
            .friendsFeed(cursorScore: cursorScore, cursorID: cursorID, limit: limit)
        )
    }

    /// v2: Discovery feed with daily cap enforcement
    func fetchDiscovery(limit: Int = 10) async throws -> FeedPage {
        return try await client.request(
            .explorePosts(limit: limit)
        )
    }

    func recordExposures(authorIDs: [UUID]) async throws {
        try await client.requestVoid(.recordExposures(authorIDs: authorIDs))
    }

    /// v2: Fire-and-forget consumption tracking for finite feed state
    func recordConsumption(postID: UUID, feedType: String) async throws {
        try await client.requestVoid(.recordConsumption(postID: postID, feedType: feedType))
    }
}
