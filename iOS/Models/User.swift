import Foundation

struct User: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let username: String
    let displayName: String?
    let profilePhotoURL: String?
    let bio: String?
    let visibility: AccountVisibility
    let instagramHandle: String?
    let snapchatHandle: String?
    let totalLikes: Int
    let followerCount: Int
    let followingCount: Int
    let commentsEnabled: Bool
    let lastPostAt: Date?
    let createdAt: Date

    enum AccountVisibility: String, Codable, Sendable {
        case `public`
        case `private`
    }
}

struct UserProfile: Decodable, Sendable {
    let userId: UUID
    let username: String
    let displayName: String?
    let profilePhotoURL: String?
    let bio: String?
    let visibility: User.AccountVisibility
    let instagramHandle: String?
    let snapchatHandle: String?
    let totalLikes: Int
    let followerCount: Int
    let followingCount: Int
    let commentsEnabled: Bool
    let isFollowing: Bool
    let isFollower: Bool
    let followIsPending: Bool
    let isOwnProfile: Bool
    let onboardingCompletedAt: Date?
    let signaturePosts: [PostSummary]
    let livePosts: [PostSummary]

    enum CodingKeys: String, CodingKey {
        case userId
        case username, displayName, bio, visibility
        case profilePhotoURL = "profilePhotoUrl"
        case instagramHandle, snapchatHandle
        case totalLikes, followerCount, followingCount
        case commentsEnabled
        case isFollowing, isFollower, followIsPending, isOwnProfile
        case onboardingCompletedAt
        case signaturePosts, livePosts
    }
}

struct PostSummary: Codable, Identifiable, Sendable {
    let id: UUID
    let imageURL: String
    let imageWidth: Int
    let imageHeight: Int
    let likeCount: Int
    let createdAt: Date
    let tags: [Tag]

    enum CodingKeys: String, CodingKey {
        case id
        case imageURL = "imageUrl"
        case imageWidth, imageHeight, likeCount, createdAt, tags
    }
}
