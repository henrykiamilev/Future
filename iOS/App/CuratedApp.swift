import SwiftUI
import Combine

@main
struct CuratedApp: App {

    @StateObject private var appState = AppState()
    @State private var showSplash = true
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if showOnboarding {
                        OnboardingView {
                            Task {
                                if let uid = appState.authService.currentUserID {
                                    try? await appState.profileService.completeOnboarding(userID: uid)
                                }
                            }
                            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                            withAnimation { showOnboarding = false }
                        }
                    } else if appState.isAuthenticated {
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
            .onChange(of: appState.isAuthenticated) { _, isAuth in
                if isAuth {
                    // Check local cache first for instant UI
                    guard !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") else { return }
                    // Verify against server to prevent infinite loop and handle reinstalls
                    Task {
                        guard let userID = appState.authService.currentUserID else {
                            showOnboarding = true
                            return
                        }
                        do {
                            let profile = try await appState.profileService.fetchProfile(userID: userID)
                            if profile.onboardingCompletedAt == nil {
                                showOnboarding = true
                            } else {
                                // Sync local cache from server (handles reinstall / new device)
                                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                            }
                        } catch {
                            // New user or network issue — show onboarding to be safe
                            showOnboarding = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supabase Configuration

enum SupabaseConfig {
    // These should be loaded from a plist or environment in production.
    // The anon key is safe to embed client-side — RLS protects data.
    static let projectURL = URL(string: "https://rylyzntjznnwmysszbzq.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ5bHl6bnRqem5ud215c3N6YnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3NzIyNjIsImV4cCI6MjA4NjM0ODI2Mn0.IX-4kN7OAdrid-Frg-E3iV7wZzZD3hWhWq7zfEJ2Xn8"
    static let storageBucket = "posts"

    /// Builds an authenticated storage URL from a relative path (e.g. `"uploads/abc.heic"`).
    /// Full URLs (starting with "http") pass through unchanged for backward compatibility
    /// during the migration window.
    static func storageURL(for path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        // Backward compat: full URLs pass through during migration window
        if path.hasPrefix("http") { return URL(string: path) }
        // Authenticated endpoint — no /public/ segment
        return projectURL.appendingPathComponent("storage/v1/object/\(storageBucket)/\(path)")
    }
}

// MARK: - App-Wide Dependency Container

@MainActor
final class AppState: ObservableObject {

    // Infrastructure
    let tokenProvider: KeychainTokenProvider
    let apiClient: APIClient
    let urlSession: URLSession

    // Services
    let authService: AuthService
    let feedService: FeedService
    let postService: PostService
    let profileService: ProfileService
    let imageUploadService: ImageUploadService
    let searchService: SearchService
    let commentService: CommentService
    let notificationService: NotificationService

    @Published var isAuthenticated = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        let token = KeychainTokenProvider()

        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = URLCache(
            memoryCapacity: 50_000_000,
            diskCapacity: 200_000_000
        )
        config.requestCachePolicy = .useProtocolCachePolicy
        let session = URLSession(configuration: config)

        let client = APIClient(
            baseURL: SupabaseConfig.projectURL,
            session: session,
            tokenProvider: token,
            supabaseAnonKey: SupabaseConfig.anonKey
        )

        self.tokenProvider = token
        self.urlSession = session
        self.apiClient = client
        self.authService = AuthService(client: client, tokenProvider: token)
        self.feedService = FeedService(client: client)
        self.postService = PostService(client: client)
        self.profileService = ProfileService(client: client)
        self.imageUploadService = ImageUploadService(
            baseURL: SupabaseConfig.projectURL,
            anonKey: SupabaseConfig.anonKey,
            tokenProvider: token,
            bucket: SupabaseConfig.storageBucket
        )
        self.searchService = SearchService(client: client)
        self.commentService = CommentService(client: client)
        self.notificationService = NotificationService(client: client)

        self.isAuthenticated = token.currentToken != nil

        // Configure ImageCache with auth for private storage bucket
        ImageCache.shared.configure(
            tokenProvider: { [weak token] in token?.currentToken },
            anonKey: SupabaseConfig.anonKey
        )

        NotificationCenter.default.publisher(for: .authSessionExpired)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.clearAllCaches()
                self?.isAuthenticated = false
            }
            .store(in: &cancellables)
    }

    // Cached view models to avoid re-allocation on every SwiftUI body evaluation
    private var cachedFeedVM: FeedViewModel?
    private var cachedPostVM: PostViewModel?
    private var cachedProfileVMs: [UUID: ProfileViewModel] = [:]
    private var cachedSettingsVM: SettingsViewModel?
    private var cachedSearchVM: SearchViewModel?

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
        let auth = authService
        let vm = ProfileViewModel(userID: userID, currentUserIDProvider: { auth.currentUserID }, profileService: profileService, postService: postService)
        // Cap cache at 20 entries to prevent unbounded memory growth
        if cachedProfileVMs.count >= 20 {
            cachedProfileVMs.removeAll()
        }
        cachedProfileVMs[userID] = vm
        return vm
    }

    func makeSettingsViewModel() -> SettingsViewModel? {
        if let vm = cachedSettingsVM { return vm }
        guard let uid = authService.currentUserID else {
            print("[AppState] makeSettingsViewModel called without authenticated user")
            return nil
        }
        let vm = SettingsViewModel(
            profileService: profileService,
            authService: authService,
            imageUploadService: imageUploadService,
            currentUserID: uid
        )
        cachedSettingsVM = vm
        return vm
    }

    func makeSearchViewModel() -> SearchViewModel {
        if let vm = cachedSearchVM { return vm }
        let vm = SearchViewModel(searchService: searchService)
        cachedSearchVM = vm
        return vm
    }

    func makePostDetailViewModel(post: FeedPost, commentsEnabled: Bool) -> PostDetailViewModel {
        PostDetailViewModel(
            post: post,
            commentsEnabled: commentsEnabled,
            commentService: commentService,
            postService: postService
        )
    }

    func makeFollowListViewModel(userID: UUID) -> FollowListViewModel {
        FollowListViewModel(userID: userID, profileService: profileService)
    }

    /// Clears all in-memory and URL caches. Called on sign-out to prevent data leaking between accounts.
    func clearAllCaches() {
        cachedFeedVM = nil
        cachedPostVM = nil
        cachedProfileVMs.removeAll()
        cachedSettingsVM = nil
        cachedSearchVM = nil
        urlSession.configuration.urlCache?.removeAllCachedResponses()
        ImageCache.shared.clearDiskCache()
    }
}
