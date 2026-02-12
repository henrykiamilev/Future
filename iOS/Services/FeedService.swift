import Foundation

protocol FeedServiceProtocol: Sendable {
    func fetchMainFeed(cursor: FeedCursor?, limit: Int) async throws -> FeedPage
    func fetchFriendsFeed(cursor: FeedCursor?, limit: Int) async throws -> FeedPage
    func recordExposures(authorIDs: [UUID]) async throws
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

        // Record exposures for returned authors (structured — awaited inline)
        let authorIDs = Array(Set(page.posts.map(\.userID)))
        if !authorIDs.isEmpty {
            try? await recordExposures(authorIDs: authorIDs)
        }

        return page
    }

    func fetchFriendsFeed(cursor: FeedCursor? = nil, limit: Int = 20) async throws -> FeedPage {
        var cursorDate: Date?
        if case .chronological(let date) = cursor {
            cursorDate = date
        }

        return try await client.request(
            .friendsFeed(cursor: cursorDate, limit: limit)
        )
    }

    func recordExposures(authorIDs: [UUID]) async throws {
        try await client.requestVoid(.recordExposures(authorIDs: authorIDs))
    }
}
