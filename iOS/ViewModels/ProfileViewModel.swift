import Foundation
import Combine

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    // Streak
    @Published private(set) var streakCount: Int = 0

    // Archive
    @Published private(set) var archivePosts: [ArchivePost] = []
    @Published private(set) var isLoadingArchive = false
    @Published private(set) var showArchive = false

    private var archiveCursor: Date?
    private var archiveHasMore = true

    // MARK: - Dependencies

    private let profileService: ProfileServiceProtocol
    private let postService: PostServiceProtocol
    let userID: UUID
    /// Dynamic provider — always reads the latest currentUserID from the auth service,
    /// avoiding stale nil values from cached ViewModels.
    private let currentUserIDProvider: () -> UUID?

    init(userID: UUID, currentUserIDProvider: @escaping () -> UUID?, profileService: ProfileServiceProtocol, postService: PostServiceProtocol) {
        self.userID = userID
        self.currentUserIDProvider = currentUserIDProvider
        self.profileService = profileService
        self.postService = postService
    }

    /// Convenience init for backward compatibility (tests, previews)
    convenience init(userID: UUID, currentUserID: UUID? = nil, profileService: ProfileServiceProtocol, postService: PostServiceProtocol) {
        self.init(userID: userID, currentUserIDProvider: { currentUserID }, profileService: profileService, postService: postService)
    }

    // MARK: - Convenience Accessors

    var username: String { profile?.username ?? "" }
    var displayName: String? { profile?.displayName }
    var profilePhotoURL: String? { profile?.profilePhotoURL }
    var totalLikes: Int { profile?.totalLikes ?? 0 }
    var followerCount: Int { profile?.followerCount ?? 0 }
    var followingCount: Int { profile?.followingCount ?? 0 }
    var isOwnProfile: Bool { profile?.isOwnProfile ?? false }
    var isFollowing: Bool { profile?.isFollowing ?? false }
    var followIsPending: Bool { profile?.followIsPending ?? false }
    var signaturePosts: [PostSummary] { profile?.signaturePosts ?? [] }
    var livePosts: [PostSummary] { profile?.livePosts ?? [] }
    var instagramHandle: String? { profile?.instagramHandle }
    var snapchatHandle: String? { profile?.snapchatHandle }

    // MARK: - Load Profile

    func load() async {
        isLoading = true
        error = nil

        do {
            profile = try await profileService.fetchProfile(userID: userID)
            // Load streak if viewing someone else's profile
            if profile?.isOwnProfile == false {
                if let streak = try? await profileService.getStreakWith(userID: userID) {
                    streakCount = streak.currentStreak
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Follow / Unfollow

    func toggleFollow() async {
        guard let profile else { return }

        guard let myID = currentUserIDProvider() else {
            self.error = "Not signed in. Please restart the app."
            print("[ProfileVM] toggleFollow FAILED: currentUserID is nil")
            return
        }

        print("[ProfileVM] toggleFollow: isFollowing=\(profile.isFollowing), myID=\(myID), targetID=\(userID)")

        do {
            if profile.isFollowing {
                try await profileService.unfollow(userID: userID, currentUserID: myID)
            } else {
                try await profileService.follow(userID: userID, currentUserID: myID)
            }
            // Reload to get updated state
            await load()
        } catch {
            print("[ProfileVM] toggleFollow ERROR: \(error)")
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
