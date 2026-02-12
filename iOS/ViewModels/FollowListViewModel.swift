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
        isLoading = true
        error = nil

        do {
            async let f = profileService.getFollowers(userID: userID)
            async let g = profileService.getFollowing(userID: userID)
            followers = try await f
            following = try await g
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
