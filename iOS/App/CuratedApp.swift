import SwiftUI

@main
struct CuratedApp: App {

    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
    }
}

// MARK: - App-Wide Dependency Container

@MainActor
final class AppState: ObservableObject {

    // Infrastructure
    let tokenProvider: KeychainTokenProvider
    let apiClient: APIClient

    // Services
    let authService: AuthService
    let feedService: FeedService
    let postService: PostService
    let profileService: ProfileService
    let imageUploadService: ImageUploadService

    @Published var isAuthenticated = false

    init() {
        let token = KeychainTokenProvider()
        let baseURL = URL(string: "https://api.example.com/v1")!
        let client = APIClient(baseURL: baseURL, tokenProvider: token)

        self.tokenProvider = token
        self.apiClient = client
        self.authService = AuthService(client: client, tokenProvider: token)
        self.feedService = FeedService(client: client)
        self.postService = PostService(client: client)
        self.profileService = ProfileService(client: client)
        self.imageUploadService = ImageUploadService(client: client)

        self.isAuthenticated = token.currentToken != nil
    }

    func makeFeedViewModel() -> FeedViewModel {
        FeedViewModel(feedService: feedService, postService: postService)
    }

    func makePostViewModel() -> PostViewModel {
        PostViewModel(imageUploadService: imageUploadService, postService: postService)
    }

    func makeProfileViewModel(userID: UUID) -> ProfileViewModel {
        ProfileViewModel(userID: userID, profileService: profileService, postService: postService)
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(profileService: profileService, authService: authService)
    }
}
