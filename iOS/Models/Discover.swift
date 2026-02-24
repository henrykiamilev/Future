import Foundation

struct SuggestedUser: Decodable, Identifiable, Sendable {
    let id: UUID
    let username: String
    let displayName: String?
    let profilePhotoURL: String?
    let followerCount: Int

    enum CodingKeys: String, CodingKey {
        case id, username, displayName
        case profilePhotoURL = "profilePhotoUrl"
        case followerCount
    }
}

struct ExplorePost: Decodable, Identifiable, Hashable, Sendable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ExplorePost, rhs: ExplorePost) -> Bool { lhs.id == rhs.id }

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
    let likeCount: Int
    let createdAt: Date
    let score: Double

    // v2: Discovery finite feed metadata
    let isExhausted: Bool?
    let itemsRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "userId"
        case username, authorPhoto, displayName, caption, location
        case imageURL = "imageUrl"
        case imageWidth, imageHeight, likeCount, createdAt, score
        case isExhausted, itemsRemaining
    }

    var asFeedPost: FeedPost {
        FeedPost(
            id: id,
            userID: userID,
            username: username,
            authorPhoto: authorPhoto,
            displayName: displayName,
            caption: caption,
            location: location,
            imageURL: imageURL,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            likeCount: likeCount,
            viewCount: 0,
            isLiked: false,
            createdAt: createdAt,
            score: score,
            tags: [],
            feedScore: nil,
            isCaughtUp: nil,
            friendsRemaining: nil,
            isExhausted: isExhausted,
            itemsRemaining: itemsRemaining
        )
    }
}
