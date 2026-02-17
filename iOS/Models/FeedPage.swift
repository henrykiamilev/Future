import Foundation

struct FeedPage: Decodable, Sendable {
    let posts: [FeedPost]
    let nextCursor: FeedCursor?
    let hasMore: Bool

    init(from decoder: Decoder) throws {
        // Server may return a raw JSON array (PostgREST) or a keyed object
        if var array = try? decoder.unkeyedContainer() {
            var posts: [FeedPost] = []
            posts.reserveCapacity(array.count ?? 0)
            while !array.isAtEnd {
                posts.append(try array.decode(FeedPost.self))
            }
            self.posts = posts
            self.nextCursor = nil
            self.hasMore = false
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.posts = try container.decode([FeedPost].self, forKey: .posts)
        self.nextCursor = try container.decodeIfPresent(FeedCursor.self, forKey: .nextCursor)
        self.hasMore = try container.decode(Bool.self, forKey: .hasMore)
    }

    private enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor
        case hasMore
    }
}

enum FeedCursor: Sendable, Equatable {
    case ranked(score: Double, id: UUID)
    case chronological(createdAt: Date)
}

extension FeedCursor: Decodable {
    enum CodingKeys: String, CodingKey {
        case score, id, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let score = try container.decodeIfPresent(Double.self, forKey: .score),
           let id = try container.decodeIfPresent(UUID.self, forKey: .id) {
            self = .ranked(score: score, id: id)
        } else if let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            self = .chronological(createdAt: createdAt)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid cursor format")
            )
        }
    }
}

extension FeedCursor: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ranked(let score, let id):
            try container.encode(score, forKey: .score)
            try container.encode(id, forKey: .id)
        case .chronological(let createdAt):
            try container.encode(createdAt, forKey: .createdAt)
        }
    }
}
