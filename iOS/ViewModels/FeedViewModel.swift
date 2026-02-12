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

    // Memory cap: keep at most this many posts in memory.
    // Older posts are dropped from the front when new pages arrive.
    private let maxPostsInMemory = 100

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

            // Memory cap: drop oldest posts if we exceed the limit
            if posts.count > maxPostsInMemory {
                let overflow = posts.count - maxPostsInMemory
                posts.removeFirst(overflow)
            }
        } catch {
            // Silently fail on pagination — user can scroll again
        }

        isLoadingMore = false
    }

    func toggleLike(post: FeedPost) async {
        // Capture the post ID for stable lookup — avoids index-based race condition
        let postID = post.id

        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }

        // Optimistic update
        let wasLiked = posts[index].isLiked
        posts[index].isLiked = !wasLiked

        do {
            let response = wasLiked
                ? try await postService.unlikePost(id: postID)
                : try await postService.likePost(id: postID)

            // Re-lookup by ID after the async call — the index may have shifted
            if let idx = posts.firstIndex(where: { $0.id == postID }) {
                posts[idx].isLiked = !wasLiked
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
            // Revert optimistic update — re-lookup by ID, not stale index
            if let idx = posts.firstIndex(where: { $0.id == postID }) {
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
