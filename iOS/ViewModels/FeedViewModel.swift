import Foundation

enum FeedSegment: String, CaseIterable, Sendable {
    case friends = "Friends"
    case main = "Main"
}

@MainActor
final class FeedViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var posts: [FeedPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published var selectedSegment: FeedSegment = .friends {
        didSet {
            if oldValue != selectedSegment {
                Task { await refresh() }
            }
        }
    }

    // MARK: - Pagination State

    private var nextCursor: FeedCursor?
    private var hasMore = true
    private var loadTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let feedService: FeedServiceProtocol
    private let postService: PostServiceProtocol

    init(feedService: FeedServiceProtocol, postService: PostServiceProtocol) {
        self.feedService = feedService
        self.postService = postService
    }

    // MARK: - Public Actions

    func loadInitial() async {
        guard posts.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        loadTask?.cancel()
        isLoading = true
        error = nil
        nextCursor = nil
        hasMore = true

        loadTask = Task {
            do {
                let page = try await fetchPage(cursor: nil)
                guard !Task.isCancelled else { return }
                posts = page.posts
                nextCursor = page.nextCursor
                hasMore = page.hasMore
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
        await loadTask?.value
    }

    func loadMoreIfNeeded(currentPost: FeedPost) async {
        guard hasMore,
              !isLoadingMore,
              let last = posts.last,
              currentPost.id == last.id else { return }

        isLoadingMore = true

        do {
            let page = try await fetchPage(cursor: nextCursor)
            posts.append(contentsOf: page.posts)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            // Silently fail on pagination — user can scroll again
        }

        isLoadingMore = false
    }

    func toggleLike(post: FeedPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }

        // Optimistic update
        let wasLiked = posts[index].isLiked
        posts[index].isLiked = !wasLiked

        do {
            let response = wasLiked
                ? try await postService.unlikePost(id: post.id)
                : try await postService.likePost(id: post.id)

            if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                posts[idx] = FeedPost(
                    id: posts[idx].id,
                    userID: posts[idx].userID,
                    username: posts[idx].username,
                    authorPhoto: posts[idx].authorPhoto,
                    imageURL: posts[idx].imageURL,
                    imageWidth: posts[idx].imageWidth,
                    imageHeight: posts[idx].imageHeight,
                    likeCount: response.newLikeCount,
                    viewCount: posts[idx].viewCount,
                    isLiked: !wasLiked,
                    createdAt: posts[idx].createdAt,
                    score: posts[idx].score,
                    tags: posts[idx].tags
                )
            }
        } catch {
            // Revert optimistic update
            if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                posts[idx].isLiked = wasLiked
            }
        }
    }

    // MARK: - Private

    private func fetchPage(cursor: FeedCursor?) async throws -> FeedPage {
        switch selectedSegment {
        case .main:
            return try await feedService.fetchMainFeed(cursor: cursor, limit: 20)
        case .friends:
            return try await feedService.fetchFriendsFeed(cursor: cursor, limit: 20)
        }
    }
}
