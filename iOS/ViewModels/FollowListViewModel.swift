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

        // Load independently so one failure doesn't block the other
        async let f: Result<[UserSummary], Error> = {
            do { return .success(try await profileService.getFollowers(userID: userID)) }
            catch { return .failure(error) }
        }()
        async let g: Result<[UserSummary], Error> = {
            do { return .success(try await profileService.getFollowing(userID: userID)) }
            catch { return .failure(error) }
        }()

        let followersResult = await f
        let followingResult = await g

        switch followersResult {
        case .success(let list): followers = list
        case .failure(let err): self.error = err.localizedDescription
        }

        switch followingResult {
        case .success(let list): following = list
        case .failure(let err):
            // Only overwrite error if we didn't already have one
            if self.error == nil { self.error = err.localizedDescription }
        }

        isLoading = false
    }
}
