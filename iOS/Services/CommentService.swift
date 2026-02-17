import Foundation

protocol CommentServiceProtocol: Sendable {
    func getComments(postID: UUID, cursor: Date?, limit: Int) async throws -> CommentsPage
    func addComment(postID: UUID, content: String) async throws -> Comment
    func deleteComment(commentID: UUID) async throws
}

final class CommentService: CommentServiceProtocol, Sendable {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func getComments(postID: UUID, cursor: Date? = nil, limit: Int = 30) async throws -> CommentsPage {
        try await client.request(.getComments(postID: postID, cursor: cursor, limit: limit))
    }

    func addComment(postID: UUID, content: String) async throws -> Comment {
        try await client.request(.addComment(postID: postID, content: content))
    }

    func deleteComment(commentID: UUID) async throws {
        try await client.requestVoid(.deleteComment(commentID: commentID))
    }
}
