import SwiftUI

@main
struct CuratedApp: App {

    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    MainTabView()
                } else {
                    AuthView()
                }
            }
            .environmentObject(appState)
            .preferredColorScheme(.light)
        }
    }
}

// MARK: - Supabase Configuration

enum SupabaseConfig {
    // These should be loaded from a plist or environment in production.
    // The anon key is safe to embed client-side — RLS protects data.
    static let projectURL = URL(string: "https://rylyzntjznnwmysszbzq.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ5bHl6bnRqem5ud215c3N6YnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3NzIyNjIsImV4cCI6MjA4NjM0ODI2Mn0.IX-4kN7OAdrid-Frg-E3iV7wZzZD3hWhWq7zfEJ2Xn8"
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
