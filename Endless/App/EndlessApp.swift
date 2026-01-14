import SwiftUI

@main
struct EndlessApp: App {
    @StateObject private var appState = AppState()

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
final class AppState: ObservableObject {
    // Navigation state
    @Published var currentScreen: AppScreen = .launch

    // User session
    @Published var isAuthenticated: Bool = false
    @Published var hasCompletedOnboarding: Bool = false

    // Preferences
    @Published var prefersDarkMode: Bool? = nil

    // Computed color scheme
    var colorScheme: ColorScheme? {
        guard let prefersDarkMode = prefersDarkMode else { return nil }
        return prefersDarkMode ? .dark : .light
    }

    // MARK: - Navigation

    func navigateTo(_ screen: AppScreen) {
        withAnimation(Theme.Animation.standard) {
            currentScreen = screen
        }
    }

    func completelaunch() {
        if isAuthenticated {
            if hasCompletedOnboarding {
                navigateTo(.home)
            } else {
                navigateTo(.aiIntake)
            }
        } else {
            navigateTo(.authentication)
        }
    }

    func completeAuthentication() {
        isAuthenticated = true
        if hasCompletedOnboarding {
            navigateTo(.home)
        } else {
            navigateTo(.aiIntake)
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        navigateTo(.paywall)
    }

    func completePaywall() {
        navigateTo(.home)
    }

    func signOut() {
        isAuthenticated = false
        hasCompletedOnboarding = false
        navigateTo(.authentication)
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
