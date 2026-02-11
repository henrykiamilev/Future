import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    // Archive
    @Published private(set) var archivePosts: [ArchivePost] = []
    @Published private(set) var isLoadingArchive = false
    @Published private(set) var showArchive = false

    private var archiveCursor: Date?
    private var archiveHasMore = true

    // MARK: - Dependencies

    private let profileService: ProfileServiceProtocol
    private let postService: PostServiceProtocol
    private let userID: UUID

    init(userID: UUID, profileService: ProfileServiceProtocol, postService: PostServiceProtocol) {
        self.userID = userID
        self.profileService = profileService
        self.postService = postService
    }

    // MARK: - Convenience Accessors

    var username: String { profile?.user.username ?? "" }
    var displayName: String? { profile?.user.displayName }
    var profilePhotoURL: String? { profile?.user.profilePhotoURL }
    var totalLikes: Int { profile?.user.totalLikes ?? 0 }
    var followerCount: Int { profile?.user.followerCount ?? 0 }
    var followingCount: Int { profile?.user.followingCount ?? 0 }
    var isOwnProfile: Bool { profile?.user.isOwnProfile ?? false }
    var isFollowing: Bool { profile?.user.isFollowing ?? false }
    var followIsPending: Bool { profile?.user.followIsPending ?? false }
    var signaturePosts: [PostSummary] { profile?.signaturePosts ?? [] }
    var livePosts: [PostSummary] { profile?.livePosts ?? [] }
    var instagramHandle: String? { profile?.user.instagramHandle }
    var snapchatHandle: String? { profile?.user.snapchatHandle }

    // MARK: - Load Profile

    func load() async {
        isLoading = true
        error = nil

        do {
            profile = try await profileService.fetchProfile(userID: userID)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Follow / Unfollow

    func toggleFollow() async {
        guard let profile else { return }

        do {
            if profile.user.isFollowing {
                try await profileService.unfollow(userID: userID)
            } else {
                try await profileService.follow(userID: userID)
            }
            // Reload to get updated state
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Signature Management

    func addToSignature(postID: UUID) async {
        do {
            try await postService.addToSignature(postID: postID)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeFromSignature(postID: UUID) async {
        do {
            try await postService.removeFromSignature(postID: postID)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Archive

    func toggleArchive() {
        showArchive.toggle()
        if showArchive && archivePosts.isEmpty {
            Task { await loadArchive() }
        }
    }

    func loadArchive() async {
        guard isOwnProfile else { return }
        isLoadingArchive = true

        do {
            let page = try await profileService.fetchArchive(cursor: nil, limit: 30)
            archivePosts = page.posts
            archiveCursor = page.nextCursor
            archiveHasMore = page.hasMore
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingArchive = false
    }

    func loadMoreArchive() async {
        guard archiveHasMore, !isLoadingArchive else { return }
        isLoadingArchive = true

        do {
            let page = try await profileService.fetchArchive(cursor: archiveCursor, limit: 30)
            archivePosts.append(contentsOf: page.posts)
            archiveCursor = page.nextCursor
            archiveHasMore = page.hasMore
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingArchive = false
    }
}
