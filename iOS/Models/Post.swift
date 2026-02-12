import Foundation

struct FeedPost: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let username: String
    let authorPhoto: String?
    let imageURL: String
    let imageWidth: Int
    let imageHeight: Int
    var likeCount: Int
    let viewCount: Int
    var isLiked: Bool
    let createdAt: Date
    let score: Double?
    let tags: [Tag]

    // Equatable auto-synthesized — compares all properties so SwiftUI
    // re-renders cells when isLiked or likeCount changes.

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "userId"
        case username
        case authorPhoto
        case imageURL = "imageUrl"
        case imageWidth
        case imageHeight
        case likeCount
        case viewCount
        case isLiked
        case createdAt
        case score
        case tags
    }
}

struct CreatePostRequest: Encodable, Sendable {
    let imageURL: String
    let imageWidth: Int
    let imageHeight: Int
    let imageSizeBytes: Int
    let tags: [TagInput]

    enum CodingKeys: String, CodingKey {
        case imageURL = "imageUrl"
        case imageWidth
        case imageHeight
        case imageSizeBytes
        case tags
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
