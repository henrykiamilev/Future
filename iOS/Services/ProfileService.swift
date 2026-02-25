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
    func getStreakWith(userID: UUID) async throws -> StreakInfo?
    func getMyStreaks() async throws -> [StreakPartner]
    func getCuratedPage(userID: UUID) async throws -> CuratedPage?
    func upsertCuratedPage(_ update: CuratedPageUpdate) async throws
}

struct StreakInfo: Decodable, Sendable {
    let currentStreak: Int
    let longestStreak: Int
}

struct StreakPartner: Decodable, Identifiable, Sendable {
    let partnerId: UUID
    let partnerUsername: String
    let partnerPhoto: String?
    let currentStreak: Int
    let longestStreak: Int

    var id: UUID { partnerId }
}

// MARK: - Curated Page

struct CuratedPage: Decodable, Sendable {
    let userId: UUID
    let username: String
    let displayName: String?
    let profilePhotoUrl: String?
    let instagramHandle: String?
    let snapchatHandle: String?
    let image1: String?
    let image2: String?
    let image3: String?
    let image4: String?
    let q1Prompt: String?
    let q1Answer: String?
    let q2Prompt: String?
    let q2Answer: String?
    let q3Prompt: String?
    let q3Answer: String?
    let q4Prompt: String?
    let q4Answer: String?

    var images: [String] {
        [image1, image2, image3, image4].compactMap { $0 }
    }

    var qaPairs: [(prompt: String, answer: String)] {
        [(q1Prompt, q1Answer), (q2Prompt, q2Answer), (q3Prompt, q3Answer), (q4Prompt, q4Answer)]
            .compactMap { prompt, answer in
                guard let p = prompt, !p.isEmpty, let a = answer, !a.isEmpty else { return nil }
                return (p, a)
            }
    }
}

struct ArchivePage: Decodable, Sendable {
    let posts: [ArchivePost]
    let nextCursor: Date?
    let hasMore: Bool
}

// MARK: - PostgREST Embedded Row Wrappers
// The follows table returns embedded user objects like {"follower": {...}} or {"following": {...}}

struct FollowerRow: Decodable, Sendable {
    let follower: UserSummary?
}

struct FollowingRow: Decodable, Sendable {
    let following: UserSummary?
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
        print("[ProfileService] getFollowers: querying for userID=\(userID)")
        let rows: [FollowerRow] = try await client.request(.followers(userID: userID))
        let result = rows.compactMap { $0.follower }
        print("[ProfileService] getFollowers: returned \(result.count) users")
        return result
    }

    func getFollowing(userID: UUID) async throws -> [UserSummary] {
        print("[ProfileService] getFollowing: querying for userID=\(userID)")
        let rows: [FollowingRow] = try await client.request(.following(userID: userID))
        let result = rows.compactMap { $0.following }
        print("[ProfileService] getFollowing: returned \(result.count) users")
        return result
    }

    func deleteAccount() async throws {
        try await client.requestVoid(.deleteAccount)
    }

    func completeOnboarding(userID: UUID) async throws {
        try await client.requestVoid(.completeOnboarding(userID: userID))
    }

    func getStreakWith(userID: UUID) async throws -> StreakInfo? {
        let results: [StreakInfo] = try await client.request(.getStreakWith(userID: userID))
        return results.first
    }

    func getMyStreaks() async throws -> [StreakPartner] {
        try await client.request(.getMyStreaks())
    }

    func getCuratedPage(userID: UUID) async throws -> CuratedPage? {
        let results: [CuratedPage] = try await client.request(.getCuratedPage(userID: userID))
        return results.first
    }

    func upsertCuratedPage(_ update: CuratedPageUpdate) async throws {
        try await client.requestVoid(.upsertCuratedPage(update))
    }
}
