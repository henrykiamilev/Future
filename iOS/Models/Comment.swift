import Foundation

struct Comment: Codable, Identifiable, Sendable {
    let id: UUID
    let postID: UUID
    let userID: UUID
    let username: String
    let authorPhoto: String?
    let content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "postId"
        case userID = "userId"
        case username
        case authorPhoto
        case content
        case createdAt
    }
}

struct CommentsPage: Decodable, Sendable {
    let comments: [Comment]
    let hasMore: Bool
}

struct UserSummary: Codable, Identifiable, Sendable {
    let id: UUID
    let username: String
    let displayName: String?
    let profilePhotoURL: String?

    enum CodingKeys: String, CodingKey {
        case id, username, displayName
        case profilePhotoURL = "profilePhotoUrl"
    }
}
