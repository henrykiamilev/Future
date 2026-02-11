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

// MARK: - Supabase Configuration

enum SupabaseConfig {
    // These should be loaded from a plist or environment in production.
    // The anon key is safe to embed client-side — RLS protects data.
    static let projectURL = URL(string: "https://YOUR_PROJECT.supabase.co")!
    static let anonKey = "YOUR_SUPABASE_ANON_KEY"
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
        let client = APIClient(
            baseURL: SupabaseConfig.projectURL,
            tokenProvider: token,
            supabaseAnonKey: SupabaseConfig.anonKey
        )

        self.tokenProvider = token
        self.apiClient = client
        self.authService = AuthService(client: client, tokenProvider: token)
        self.feedService = FeedService(client: client)
        self.postService = PostService(client: client)
        self.profileService = ProfileService(client: client)
        self.imageUploadService = ImageUploadService(
            baseURL: SupabaseConfig.projectURL,
            anonKey: SupabaseConfig.anonKey,
            tokenProvider: token
        )

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
