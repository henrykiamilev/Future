import Foundation

struct FeedPost: Codable, Identifiable, Equatable, Hashable, Sendable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: UUID
    let userID: UUID
    let username: String
    let authorPhoto: String?
    let displayName: String?
    let caption: String?
    let location: String?
    let imageURL: String
    let imageWidth: Int
    let imageHeight: Int
    var likeCount: Int
    let viewCount: Int
    var isLiked: Bool
    let createdAt: Date
    let score: Double?
    let tags: [Tag]

    // v2: Ranked friends feed score + finite feed metadata
    let feedScore: Double?
    let isCaughtUp: Bool?
    let friendsRemaining: Int?

    // v2: Discovery finite feed metadata
    let isExhausted: Bool?
    let itemsRemaining: Int?

    // Equatable auto-synthesized — compares all properties so SwiftUI
    // re-renders cells when isLiked or likeCount changes.

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "userId"
        case username
        case authorPhoto
        case displayName
        case caption
        case location
        case imageURL = "imageUrl"
        case imageWidth
        case imageHeight
        case likeCount
        case viewCount
        case isLiked
        case createdAt
        case score
        case tags
        case feedScore
        case isCaughtUp
        case friendsRemaining
        case isExhausted
        case itemsRemaining
    }
}

struct CreatePostRequest: Encodable, Sendable {
    let imageURL: String
    let imageWidth: Int
    let imageHeight: Int
    let imageSizeBytes: Int
    let tags: [TagInput]
    let caption: String?
    let location: String?

    enum CodingKeys: String, CodingKey {
        case imageURL = "imageUrl"
        case imageWidth
        case imageHeight
        case imageSizeBytes
        case tags
        case caption
        case location
    }
}

struct CreatePostResponse: Decodable, Sendable {
    let postID: UUID
    let expiresAt: Date
    let nextPostAllowedAt: Date

    enum CodingKeys: String, CodingKey {
        case postID = "postId"
        case expiresAt
        case nextPostAllowedAt
    }
}

struct LikeResponse: Decodable, Sendable {
    let newLikeCount: Int
}

struct ArchivePost: Codable, Identifiable, Sendable {
    let id: UUID
    let imageURL: String
    let likeCount: Int
    let isSignature: Bool
    let isActive: Bool
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case imageURL = "imageUrl"
        case likeCount
        case isSignature
        case isActive
        case createdAt
        case expiresAt
    }
}
