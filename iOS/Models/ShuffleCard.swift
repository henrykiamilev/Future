import Foundation

struct ShuffleCard: Decodable, Identifiable, Sendable {
    let id: UUID
    let username: String
    let displayName: String?
    let profilePhotoURL: String?
    let bio: String?
    let followerCount: Int
    let followingCount: Int
    let totalLikes: Int
    let postCount: Int
    let createdAt: Date
    let lastPostAt: Date?
    let signaturePost: PostSummary?
    let recentPosts: [PostSummary]

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, bio
        case followerCount, followingCount, totalLikes
        case postCount, createdAt, lastPostAt
        case profilePhotoURL = "profilePhotoUrl"
        case signaturePost, recentPosts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        profilePhotoURL = try c.decodeIfPresent(String.self, forKey: .profilePhotoURL)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        followerCount = try c.decode(Int.self, forKey: .followerCount)
        followingCount = (try? c.decode(Int.self, forKey: .followingCount)) ?? 0
        totalLikes = (try? c.decode(Int.self, forKey: .totalLikes)) ?? 0
        postCount = (try? c.decode(Int.self, forKey: .postCount)) ?? 0
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        lastPostAt = try? c.decodeIfPresent(Date.self, forKey: .lastPostAt)
        signaturePost = try? c.decodeIfPresent(PostSummary.self, forKey: .signaturePost)
        recentPosts = (try? c.decode([PostSummary].self, forKey: .recentPosts)) ?? []
    }

    // MARK: - Computed Properties

    /// Join year formatted as "'24"
    var memberSince: String {
        let year = Calendar.current.component(.year, from: createdAt)
        return "'\(String(format: "%02d", year % 100))"
    }

    /// Activity percentage: 0-100 based on days since last post
    var activityScore: Int {
        guard let lastPost = lastPostAt else { return 0 }
        let daysSince = Calendar.current.dateComponents([.day], from: lastPost, to: Date()).day ?? 999
        switch daysSince {
        case 0: return 100
        case 1: return 90
        case 2...3: return 75
        case 4...7: return 60
        case 8...14: return 40
        case 15...30: return 20
        default: return 5
        }
    }

    /// All displayable images in priority order for the mosaic
    var allImages: [PostSummary] {
        var images: [PostSummary] = []
        if let sig = signaturePost { images.append(sig) }
        images.append(contentsOf: recentPosts)
        return images
    }

    /// Unique tags across all posts, deduplicated
    var allTags: [Tag] {
        var seen = Set<String>()
        var result: [Tag] = []
        for post in allImages {
            for tag in post.tags where !seen.contains(tag.label) {
                seen.insert(tag.label)
                result.append(tag)
            }
        }
        return result
    }
}

struct ShuffleDeckResponse: Decodable, Sendable {
    let cards: [ShuffleCard]
    let isExhausted: Bool
    let itemsRemaining: Int
}
