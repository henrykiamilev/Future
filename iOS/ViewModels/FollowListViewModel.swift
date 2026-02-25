import Foundation

@MainActor
final class FollowListViewModel: ObservableObject {

    enum Segment: String, CaseIterable {
        case followers = "Followers"
        case following = "Following"
    }

    @Published var selectedSegment: Segment = .followers
    @Published private(set) var followers: [UserSummary] = []
    @Published private(set) var following: [UserSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    let userID: UUID
    private let profileService: ProfileServiceProtocol

    init(userID: UUID, profileService: ProfileServiceProtocol) {
        self.userID = userID
        self.profileService = profileService
    }

    var currentList: [UserSummary] {
        selectedSegment == .followers ? followers : following
    }

    func load() async {
        print("[FollowListVM] load() called for userID: \(userID)")
        isLoading = true
        error = nil

        // Load followers
        do {
            let list = try await profileService.getFollowers(userID: userID)
            print("[FollowListVM] getFollowers SUCCESS: \(list.count) followers")
            followers = list
        } catch {
            print("[FollowListVM] getFollowers FAILED: \(error)")
            self.error = error.localizedDescription
        }

        // Load following
        do {
            let list = try await profileService.getFollowing(userID: userID)
            print("[FollowListVM] getFollowing SUCCESS: \(list.count) following")
            following = list
        } catch {
            print("[FollowListVM] getFollowing FAILED: \(error)")
            if self.error == nil { self.error = error.localizedDescription }
        }

        print("[FollowListVM] Final state: \(followers.count) followers, \(following.count) following, error: \(error ?? "nil")")
        isLoading = false
    }
}
