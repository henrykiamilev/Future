import SwiftUI
import FirebaseCore

@main
struct EndlessApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Initialize Firebase
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.colorScheme)
        }
    }
}

// MARK: - App State

/// Global application state managing navigation and user session.
/// Integrates with real services for authentication and user data.
@MainActor
final class AppState: ObservableObject {
    // Navigation state
    @Published var currentScreen: AppScreen = .launch

    // Services
    private let authService = AuthService.shared
    private let userService = UserService.shared
    private let aiService = AIService.shared
    private let subscriptionService = SubscriptionService.shared

    // User session (derived from services)
    var isAuthenticated: Bool {
        authService.isAuthenticated
    }

    var hasCompletedOnboarding: Bool {
        userService.hasCompletedOnboarding
    }

    // Preferences
    @Published var prefersDarkMode: Bool? = nil

    // Loading state
    @Published var isLoading: Bool = false
    @Published var error: Error?

    // Computed color scheme
    var colorScheme: ColorScheme? {
        guard let prefersDarkMode = prefersDarkMode else { return nil }
        return prefersDarkMode ? .dark : .light
    }

    init() {
        // Observe auth state changes
        Task {
            await observeAuthState()
        }
    }

    // MARK: - Auth State Observation

    private func observeAuthState() async {
        // Watch for auth changes and update navigation
        for await _ in NotificationCenter.default.notifications(named: .init("AuthStateChanged")) {
            if authService.isAuthenticated {
                await syncUserAndNavigate()
            } else {
                navigateTo(.authentication)
            }
        }
    }

    // MARK: - Navigation

    func navigateTo(_ screen: AppScreen) {
        withAnimation(Theme.Animation.standard) {
            currentScreen = screen
        }
    }

    func completeLaunch() {
        Task {
            if authService.isAuthenticated {
                await syncUserAndNavigate()
            } else {
                navigateTo(.authentication)
            }
        }
    }

    func completeAuthentication() {
        Task {
            await syncUserAndNavigate()
        }
    }

    private func syncUserAndNavigate() async {
        isLoading = true

        do {
            // Sync user profile with backend
            let profile = try await userService.syncUser()

            // Refresh token status
            await aiService.refreshTokenStatus()

            // Navigate based on onboarding state
            if profile.hasCompletedOnboarding {
                navigateTo(.home)
            } else {
                navigateTo(.aiIntake)
            }
        } catch {
            self.error = error
            // If sync fails, still allow navigation but show error
            navigateTo(.aiIntake)
        }

        isLoading = false
    }

    func completeOnboarding() {
        // After first AI generation, show paywall
        navigateTo(.paywall)
    }

    func completePaywall() {
        // Refresh user profile to get updated subscription status
        Task {
            await userService.refreshProfile()
            await subscriptionService.refreshStatus()
            navigateTo(.home)
        }
    }

    func signOut() {
        do {
            try authService.signOut()
            userService.clearProfile()
            navigateTo(.authentication)
        } catch {
            self.error = error
        }
    }
}

// MARK: - App Screen

enum AppScreen {
    case launch         // Logo animation
    case authentication // Sign in / Create account
    case aiIntake       // Goal intake (onboarding)
    case paywall        // Subscription options
    case home           // Main calendar view
}
