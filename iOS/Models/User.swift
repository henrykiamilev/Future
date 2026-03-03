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
    let tiktokHandle: String?
    let xHandle: String?
    let websiteURL: String?
    let totalLikes: Int
    let followerCount: Int
    let followingCount: Int
    let commentsEnabled: Bool
    let lastPostAt: Date?
    let createdAt: Date
    let profileTheme: String?
    let notifyLikes: Bool
    let notifyComments: Bool
    let notifyFollows: Bool
    let notifyReactions: Bool

    enum AccountVisibility: String, Codable, Sendable {
        case `public`
        case `private`
    }

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, bio, visibility
        case profilePhotoURL = "profilePhotoUrl"
        case instagramHandle, snapchatHandle, tiktokHandle, xHandle
        case websiteURL = "websiteUrl"
        case totalLikes, followerCount, followingCount
        case commentsEnabled, lastPostAt, createdAt
        case profileTheme, notifyLikes, notifyComments, notifyFollows, notifyReactions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        profilePhotoURL = try c.decodeIfPresent(String.self, forKey: .profilePhotoURL)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        visibility = try c.decode(AccountVisibility.self, forKey: .visibility)
        instagramHandle = try c.decodeIfPresent(String.self, forKey: .instagramHandle)
        snapchatHandle = try c.decodeIfPresent(String.self, forKey: .snapchatHandle)
        tiktokHandle = try c.decodeIfPresent(String.self, forKey: .tiktokHandle)
        xHandle = try c.decodeIfPresent(String.self, forKey: .xHandle)
        websiteURL = try c.decodeIfPresent(String.self, forKey: .websiteURL)
        totalLikes = (try? c.decode(Int.self, forKey: .totalLikes)) ?? 0
        followerCount = (try? c.decode(Int.self, forKey: .followerCount)) ?? 0
        followingCount = (try? c.decode(Int.self, forKey: .followingCount)) ?? 0
        commentsEnabled = (try? c.decode(Bool.self, forKey: .commentsEnabled)) ?? true
        lastPostAt = try? c.decodeIfPresent(Date.self, forKey: .lastPostAt)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        profileTheme = try c.decodeIfPresent(String.self, forKey: .profileTheme)
        notifyLikes = (try? c.decode(Bool.self, forKey: .notifyLikes)) ?? true
        notifyComments = (try? c.decode(Bool.self, forKey: .notifyComments)) ?? true
        notifyFollows = (try? c.decode(Bool.self, forKey: .notifyFollows)) ?? true
        notifyReactions = (try? c.decode(Bool.self, forKey: .notifyReactions)) ?? true
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
    let tiktokHandle: String?
    let xHandle: String?
    let websiteURL: String?
    let totalLikes: Int
    let followerCount: Int
    let followingCount: Int
    let commentsEnabled: Bool
    let isFollowing: Bool
    let isFollower: Bool
    let followIsPending: Bool
    let isOwnProfile: Bool
    let onboardingCompletedAt: Date?
    let profileTheme: String?
    let notifyLikes: Bool
    let notifyComments: Bool
    let notifyFollows: Bool
    let notifyReactions: Bool
    let signaturePosts: [PostSummary]
    let livePosts: [PostSummary]

    enum CodingKeys: String, CodingKey {
        case userId
        case username, displayName, bio, visibility
        case profilePhotoURL = "profilePhotoUrl"
        case instagramHandle, snapchatHandle, tiktokHandle, xHandle
        case websiteURL = "websiteUrl"
        case totalLikes, followerCount, followingCount
        case commentsEnabled
        case isFollowing, isFollower, followIsPending, isOwnProfile
        case onboardingCompletedAt
        case profileTheme, notifyLikes, notifyComments, notifyFollows, notifyReactions
        case signaturePosts, livePosts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        profilePhotoURL = try c.decodeIfPresent(String.self, forKey: .profilePhotoURL)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        visibility = try c.decode(User.AccountVisibility.self, forKey: .visibility)
        instagramHandle = try c.decodeIfPresent(String.self, forKey: .instagramHandle)
        snapchatHandle = try c.decodeIfPresent(String.self, forKey: .snapchatHandle)
        tiktokHandle = try c.decodeIfPresent(String.self, forKey: .tiktokHandle)
        xHandle = try c.decodeIfPresent(String.self, forKey: .xHandle)
        websiteURL = try c.decodeIfPresent(String.self, forKey: .websiteURL)
        totalLikes = try c.decode(Int.self, forKey: .totalLikes)
        followerCount = try c.decode(Int.self, forKey: .followerCount)
        followingCount = try c.decode(Int.self, forKey: .followingCount)
        commentsEnabled = try c.decode(Bool.self, forKey: .commentsEnabled)
        isFollowing = try c.decode(Bool.self, forKey: .isFollowing)
        isFollower = try c.decode(Bool.self, forKey: .isFollower)
        followIsPending = try c.decode(Bool.self, forKey: .followIsPending)
        isOwnProfile = try c.decode(Bool.self, forKey: .isOwnProfile)
        onboardingCompletedAt = try c.decodeIfPresent(Date.self, forKey: .onboardingCompletedAt)
        profileTheme = try c.decodeIfPresent(String.self, forKey: .profileTheme)
        notifyLikes = (try? c.decode(Bool.self, forKey: .notifyLikes)) ?? true
        notifyComments = (try? c.decode(Bool.self, forKey: .notifyComments)) ?? true
        notifyFollows = (try? c.decode(Bool.self, forKey: .notifyFollows)) ?? true
        notifyReactions = (try? c.decode(Bool.self, forKey: .notifyReactions)) ?? true
        signaturePosts = (try? c.decode([PostSummary].self, forKey: .signaturePosts)) ?? []
        livePosts = (try? c.decode([PostSummary].self, forKey: .livePosts)) ?? []
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

// MARK: - Blocked User (for blocked users list)

struct BlockedUser: Decodable, Identifiable, Sendable {
    let id: UUID
    let username: String
    let displayName: String?
    let profilePhotoURL: String?

    enum CodingKeys: String, CodingKey {
        case id, username, displayName
        case profilePhotoURL = "profilePhotoUrl"
    }
}
