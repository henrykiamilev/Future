import SwiftUI

@main
struct CuratedApp: App {

    @StateObject private var appState = AppState()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if appState.isAuthenticated {
                        MainTabView()
                    } else {
                        AuthView()
                    }
                }
                .environmentObject(appState)
                .preferredColorScheme(.light)

                if showSplash {
                    SplashScreenView {
                        showSplash = false
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
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

    private var authExpiryObserver: NSObjectProtocol?

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

        authExpiryObserver = NotificationCenter.default.addObserver(
            forName: .authSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAuthenticated = false
        }
    }

    // Cached view models to avoid re-allocation on every SwiftUI body evaluation
    private var cachedFeedVM: FeedViewModel?
    private var cachedPostVM: PostViewModel?
    private var cachedProfileVMs: [UUID: ProfileViewModel] = [:]
    private var cachedSettingsVM: SettingsViewModel?

    func makeFeedViewModel() -> FeedViewModel {
        if let vm = cachedFeedVM { return vm }
        let vm = FeedViewModel(feedService: feedService, postService: postService)
        cachedFeedVM = vm
        return vm
    }

    func makePostViewModel() -> PostViewModel {
        if let vm = cachedPostVM { return vm }
        let vm = PostViewModel(imageUploadService: imageUploadService, postService: postService)
        cachedPostVM = vm
        return vm
    }

    func makeProfileViewModel(userID: UUID) -> ProfileViewModel {
        if let vm = cachedProfileVMs[userID] { return vm }
        let vm = ProfileViewModel(userID: userID, profileService: profileService, postService: postService)
        cachedProfileVMs[userID] = vm
        return vm
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        if let vm = cachedSettingsVM { return vm }
        let vm = SettingsViewModel(profileService: profileService, authService: authService)
        cachedSettingsVM = vm
        return vm
    }
}
