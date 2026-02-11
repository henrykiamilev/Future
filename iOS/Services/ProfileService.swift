import Foundation

protocol ProfileServiceProtocol: Sendable {
    func fetchProfile(userID: UUID) async throws -> UserProfile
    func fetchArchive(cursor: Date?, limit: Int) async throws -> ArchivePage
    func updateProfile(_ update: ProfileUpdate) async throws
    func follow(userID: UUID) async throws
    func unfollow(userID: UUID) async throws
    func updateVisibility(_ visibility: User.AccountVisibility) async throws
}

struct ArchivePage: Decodable, Sendable {
    let posts: [ArchivePost]
    let nextCursor: Date?
    let hasMore: Bool
}

final class ProfileService: ProfileServiceProtocol, Sendable {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func fetchProfile(userID: UUID) async throws -> UserProfile {
        try await client.request(.profile(userID: userID))
    }

    func fetchArchive(cursor: Date? = nil, limit: Int = 20) async throws -> ArchivePage {
        try await client.request(.archive(cursor: cursor, limit: limit))
    }

    func updateProfile(_ update: ProfileUpdate) async throws {
        try await client.requestVoid(.updateProfile(update))
    }

    func follow(userID: UUID) async throws {
        try await client.requestVoid(.follow(userID: userID))
    }

    func unfollow(userID: UUID) async throws {
        try await client.requestVoid(.unfollow(userID: userID))
    }

    func updateVisibility(_ visibility: User.AccountVisibility) async throws {
        try await client.requestVoid(.updateVisibility(visibility))
    }
}
