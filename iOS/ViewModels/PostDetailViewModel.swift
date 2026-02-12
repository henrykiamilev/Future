import Foundation
import Combine

@MainActor
final class PostDetailViewModel: ObservableObject {

    // MARK: - Published State

    @Published var post: FeedPost
    @Published private(set) var comments: [Comment] = []
    @Published private(set) var isLoadingComments = false
    @Published private(set) var error: String?
    @Published var commentText: String = ""
    @Published private(set) var isSendingComment = false

    /// Whether the post author has comments enabled.
    let commentsEnabled: Bool

    private let commentService: CommentServiceProtocol
    private let postService: PostServiceProtocol
    private var commentCursor: Date?
    private var hasMoreComments = true

    init(
        post: FeedPost,
        commentsEnabled: Bool,
        commentService: CommentServiceProtocol,
        postService: PostServiceProtocol
    ) {
        self.post = post
        self.commentsEnabled = commentsEnabled
        self.commentService = commentService
        self.postService = postService
    }

    // MARK: - Load Comments

    func loadComments() async {
        guard commentsEnabled else { return }
        isLoadingComments = true

        do {
            let page = try await commentService.getComments(postID: post.id, cursor: nil, limit: 30)
            comments = page.comments
            hasMoreComments = page.hasMore
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingComments = false
    }

    func loadMoreComments() async {
        guard hasMoreComments, !isLoadingComments else { return }
        isLoadingComments = true

        do {
            let cursor = comments.last?.createdAt
            let page = try await commentService.getComments(postID: post.id, cursor: cursor, limit: 30)
            comments.append(contentsOf: page.comments)
            hasMoreComments = page.hasMore
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingComments = false
    }

    // MARK: - Add Comment

    func sendComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSendingComment = true
        do {
            let comment = try await commentService.addComment(postID: post.id, content: text)
            comments.insert(comment, at: 0)
            commentText = ""
        } catch {
            self.error = error.localizedDescription
        }
        isSendingComment = false
    }

    // MARK: - Delete Comment

    func deleteComment(_ comment: Comment) async {
        do {
            try await commentService.deleteComment(commentID: comment.id)
            comments.removeAll { $0.id == comment.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Like

    func toggleLike() async {
        let wasLiked = post.isLiked
        post.isLiked = !wasLiked

        do {
            let response = wasLiked
                ? try await postService.unlikePost(id: post.id)
                : try await postService.likePost(id: post.id)
            post.likeCount = response.newLikeCount
        } catch {
            post.isLiked = wasLiked
        }
    }
}
