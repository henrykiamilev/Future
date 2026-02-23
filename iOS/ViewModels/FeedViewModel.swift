import Foundation
import Combine

enum FeedSegment: String, CaseIterable, Sendable {
    case friends = "Friends"
    case discover = "Discover"
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

    // MARK: - v2: Finite Feed State

    @Published private(set) var isFriendsCaughtUp = false
    @Published private(set) var isDiscoveryExhausted = false
    @Published private(set) var friendsRemaining: Int = 0
    @Published private(set) var discoveryRemaining: Int = 0
    @Published private(set) var friendsPostsSeen: Int = 0
    @Published private(set) var discoveryItemsSeen: Int = 0

    // MARK: - v2: Anti-Doomscroll

    @Published var showSessionReminder = false
    private var sessionStartTime: Date?
    private var sessionTimerCancellable: AnyCancellable?
    private var lastRefreshTime: Date?
    private let refreshCooldownSeconds: TimeInterval = 30

    // MARK: - Pagination State

    private var nextCursor: FeedCursor?
    private var hasMore = true
    private var loadTask: Task<Void, Never>?

    // Memory cap: reduced from 100 to 50 to discourage long sessions
    private let maxPostsInMemory = 50

    // MARK: - Dependencies

    private let feedService: FeedServiceProtocol
    private let postService: PostServiceProtocol

    init(feedService: FeedServiceProtocol, postService: PostServiceProtocol) {
        self.feedService = feedService
        self.postService = postService
    }

    // MARK: - Session Timer (Anti-Doomscroll)

    func startSessionTracking() {
        sessionStartTime = Date()
        sessionTimerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.sessionStartTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= 600 && !self.showSessionReminder {
                    self.showSessionReminder = true
                }
            }
    }

    func dismissSessionReminder() {
        showSessionReminder = false
        sessionStartTime = Date()  // Reset — next reminder in 10 min
    }

    func stopSessionTracking() {
        sessionTimerCancellable?.cancel()
        sessionTimerCancellable = nil
    }

    // MARK: - Public Actions

    func loadInitial() async {
        guard posts.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        // Pull-to-refresh cooldown: 30 seconds
        if let last = lastRefreshTime,
           Date().timeIntervalSince(last) < refreshCooldownSeconds {
            return
        }

        loadTask?.cancel()
        isLoading = true
        error = nil
        nextCursor = nil
        hasMore = true

        // Reset finite feed state on refresh
        if selectedSegment == .friends {
            isFriendsCaughtUp = false
            friendsPostsSeen = 0
        } else {
            isDiscoveryExhausted = false
            discoveryItemsSeen = 0
        }

        loadTask = Task {
            do {
                let page = try await fetchPage(cursor: nil)
                guard !Task.isCancelled else { return }
                posts = page.posts
                nextCursor = page.nextCursor
                hasMore = page.hasMore
                updateFiniteFeedState(from: page)
            } catch is CancellationError {
                return
            } catch {
                print("[FeedVM] Feed load error (\(self.selectedSegment)): \(error)")
                self.error = error.localizedDescription
            }
            isLoading = false
        }
        await loadTask?.value
        lastRefreshTime = Date()
    }

    func loadMoreIfNeeded(currentPost: FeedPost) async {
        // Block loading more if feed has ended
        if selectedSegment == .friends && isFriendsCaughtUp { return }
        if selectedSegment == .discover && isDiscoveryExhausted { return }

        guard hasMore,
              !isLoadingMore,
              let last = posts.last,
              currentPost.id == last.id else { return }

        // Discovery uses explicit "Show more" button, not auto-load
        if selectedSegment == .discover { return }

        isLoadingMore = true

        do {
            let page = try await fetchPage(cursor: nextCursor)
            posts.append(contentsOf: page.posts)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            updateFiniteFeedState(from: page)

            // Memory cap: drop oldest posts if we exceed the limit
            if posts.count > maxPostsInMemory {
                let overflow = posts.count - maxPostsInMemory
                posts.removeFirst(overflow)
            }
        } catch {
            print("[FeedVM] Load more error: \(error)")
        }

        isLoadingMore = false
    }

    /// v2: Discovery uses explicit "Show more" button instead of auto-load
    func loadMoreDiscovery() async {
        guard selectedSegment == .discover,
              !isDiscoveryExhausted,
              !isLoadingMore else { return }

        isLoadingMore = true

        do {
            let page = try await feedService.fetchDiscovery(limit: 10)
            posts.append(contentsOf: page.posts)
            updateFiniteFeedState(from: page)
        } catch {
            print("[FeedVM] Discovery load more error: \(error)")
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
                posts[idx].likeCount = response.newLikeCount
            }
        } catch {
            // Revert optimistic update — re-lookup by ID, not stale index
            if let idx = posts.firstIndex(where: { $0.id == postID }) {
                posts[idx].isLiked = wasLiked
            }
        }
    }

    /// v2: Record that a post was seen (fire-and-forget consumption tracking)
    func recordPostSeen(_ post: FeedPost) {
        let feedType = selectedSegment == .friends ? "friends" : "discovery"
        let postID = post.id
        let service = feedService
        Task.detached {
            try? await service.recordConsumption(postID: postID, feedType: feedType)
        }
    }

    // MARK: - Report

    func reportPost(id: UUID, reason: String) async {
        do {
            try await postService.reportPost(id: id, reason: reason)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Private

    private func fetchPage(cursor: FeedCursor?) async throws -> FeedPage {
        switch selectedSegment {
        case .discover:
            return try await feedService.fetchDiscovery(limit: 10)
        case .friends:
            return try await feedService.fetchFriendsFeed(cursor: cursor, limit: 20)
        }
    }

    private func updateFiniteFeedState(from page: FeedPage) {
        if selectedSegment == .friends {
            if page.isCaughtUp || page.posts.isEmpty {
                isFriendsCaughtUp = true
            }
            friendsRemaining = page.friendsRemaining
            friendsPostsSeen += page.posts.count
        } else {
            if page.isExhausted || page.posts.isEmpty {
                isDiscoveryExhausted = true
            }
            discoveryRemaining = page.itemsRemaining
            discoveryItemsSeen += page.posts.count
        }
    }
}
