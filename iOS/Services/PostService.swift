import Foundation

protocol PostServiceProtocol: Sendable {
    func createPost(_ request: CreatePostRequest) async throws -> CreatePostResponse
    func likePost(id: UUID) async throws -> LikeResponse
    func unlikePost(id: UUID) async throws -> LikeResponse
    func checkLiked(postIDs: [UUID]) async throws -> [UUID: Bool]
    func reportPost(id: UUID, reason: String) async throws
    func addToSignature(postID: UUID) async throws
    func removeFromSignature(postID: UUID) async throws
    func reactToPost(postID: UUID, emoji: String) async throws
    func removeReaction(postID: UUID) async throws
    func getPostReactions(postIDs: [UUID]) async throws -> [ReactionSummary]
}

final class PostService: PostServiceProtocol, Sendable {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func createPost(_ request: CreatePostRequest) async throws -> CreatePostResponse {
        try await client.request(.createPost(request))
    }

    func likePost(id: UUID) async throws -> LikeResponse {
        try await client.request(.likePost(id: id))
    }

    func unlikePost(id: UUID) async throws -> LikeResponse {
        try await client.request(.unlikePost(id: id))
    }

    func checkLiked(postIDs: [UUID]) async throws -> [UUID: Bool] {
        let response: LikedCheckResponse = try await client.request(.checkLiked(postIDs: postIDs))
        return response.results
    }

    func reportPost(id: UUID, reason: String) async throws {
        try await client.requestVoid(.reportPost(id: id, reason: reason))
    }

    func addToSignature(postID: UUID) async throws {
        try await client.requestVoid(.addSignature(postID: postID))
    }

    func removeFromSignature(postID: UUID) async throws {
        try await client.requestVoid(.removeSignature(postID: postID))
    }

    func reactToPost(postID: UUID, emoji: String) async throws {
        try await client.requestVoid(.reactToPost(postID: postID, emoji: emoji))
    }

    func removeReaction(postID: UUID) async throws {
        try await client.requestVoid(.removeReaction(postID: postID))
    }

    func getPostReactions(postIDs: [UUID]) async throws -> [ReactionSummary] {
        try await client.request(.getPostReactions(postIDs: postIDs))
    }
}

struct ReactionSummary: Decodable, Sendable {
    let postId: UUID
    let emoji: String
    let count: Int
    let userReacted: Bool
}

private struct LikedCheckResponse: Decodable, Sendable {
    let results: [UUID: Bool]
}
