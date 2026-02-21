import Foundation

protocol ProfileServiceProtocol: Sendable {
    func fetchProfile(userID: UUID) async throws -> UserProfile
    func fetchArchive(cursor: Date?, limit: Int) async throws -> ArchivePage
    func updateProfile(_ update: ProfileUpdate, userID: UUID) async throws
    func follow(userID: UUID, currentUserID: UUID) async throws
    func unfollow(userID: UUID, currentUserID: UUID) async throws
    func updateVisibility(_ visibility: User.AccountVisibility, userID: UUID) async throws
    func updateCommentsEnabled(_ enabled: Bool, userID: UUID) async throws
    func updateProfilePhoto(url: String, userID: UUID) async throws
    func getFollowers(userID: UUID) async throws -> [UserSummary]
    func getFollowing(userID: UUID) async throws -> [UserSummary]
    func deleteAccount() async throws
    func completeOnboarding(userID: UUID) async throws
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
        // PostgREST returns TABLE results as a JSON array — take first element
        let results: [UserProfile] = try await client.request(.profile(userID: userID))
        guard let profile = results.first else {
            throw APIError.notFound
        }
        return profile
    }

    func fetchArchive(cursor: Date? = nil, limit: Int = 20) async throws -> ArchivePage {
        // PostgREST returns TABLE functions as flat JSON arrays
        let posts: [ArchivePost] = try await client.request(.archive(cursor: cursor, limit: limit))
        let hasMore = posts.count >= limit
        let nextCursor = posts.last?.createdAt
        return ArchivePage(posts: posts, nextCursor: nextCursor, hasMore: hasMore)
    }

    func updateProfile(_ update: ProfileUpdate, userID: UUID) async throws {
        try await client.requestVoid(.updateProfile(update, userID: userID))
    }

    func follow(userID: UUID, currentUserID: UUID) async throws {
        try await client.requestVoid(.follow(userID: userID, currentUserID: currentUserID))
    }

    func unfollow(userID: UUID, currentUserID: UUID) async throws {
        try await client.requestVoid(.unfollow(userID: userID, currentUserID: currentUserID))
    }

    func updateVisibility(_ visibility: User.AccountVisibility, userID: UUID) async throws {
        try await client.requestVoid(.updateVisibility(visibility, userID: userID))
    }

    func updateCommentsEnabled(_ enabled: Bool, userID: UUID) async throws {
        try await client.requestVoid(.updateCommentsEnabled(enabled, userID: userID))
    }

    func updateProfilePhoto(url: String, userID: UUID) async throws {
        try await client.requestVoid(.updateProfilePhoto(url: url, userID: userID))
    }

    func getFollowers(userID: UUID) async throws -> [UserSummary] {
        try await client.request(.followers(userID: userID))
    }

    func getFollowing(userID: UUID) async throws -> [UserSummary] {
        try await client.request(.following(userID: userID))
    }

    func deleteAccount() async throws {
        try await client.requestVoid(.deleteAccount)
    }

    func completeOnboarding(userID: UUID) async throws {
        try await client.requestVoid(.completeOnboarding(userID: userID))
    }
}
