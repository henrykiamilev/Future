import Foundation

// MARK: - User Service

/// Service for user profile operations via backend API.
@MainActor
final class UserService: ObservableObject {
    static let shared = UserService()

    @Published private(set) var currentProfile: UserProfileResponse?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Public Methods

    /// Sync user profile after sign in.
    /// Creates user if new, updates if existing.
    func syncUser(displayName: String? = nil) async throws -> UserProfileResponse {
        isLoading = true
        error = nil

        do {
            let request = UserSyncRequest(displayName: displayName)
            let response: UserProfileResponse = try await apiClient.post("/users/sync", body: request)
            currentProfile = response
            isLoading = false
            return response
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Get current user's profile.
    func getProfile() async throws -> UserProfileResponse {
        isLoading = true
        error = nil

        do {
            let response: UserProfileResponse = try await apiClient.get("/users/me")
            currentProfile = response
            isLoading = false
            return response
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Refresh profile from server.
    func refreshProfile() async {
        do {
            _ = try await getProfile()
        } catch {
            // Silently fail on refresh
            print("[UserService] Refresh failed: \(error)")
        }
    }

    /// Clear cached profile (on sign out).
    func clearProfile() {
        currentProfile = nil
    }

    /// Update user profile (display name, preferences).
    func updateProfile(
        displayName: String? = nil,
        notificationsEnabled: Bool? = nil,
        darkModeEnabled: Bool? = nil
    ) async throws -> UserProfileResponse {
        isLoading = true
        error = nil

        do {
            let request = UpdateProfileRequest(
                displayName: displayName,
                notificationsEnabled: notificationsEnabled,
                darkModeEnabled: darkModeEnabled
            )
            let response: UserProfileResponse = try await apiClient.put("/users/me", body: request)
            currentProfile = response
            isLoading = false
            return response
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Reset journal mode preference (requires confirmation).
    func resetJournalMode() async throws -> UserProfileResponse {
        isLoading = true
        error = nil

        do {
            let request = ResetJournalModeRequest(resetJournalMode: true)
            let response: UserProfileResponse = try await apiClient.post("/users/me/reset-journal-mode", body: request)
            currentProfile = response
            isLoading = false
            return response
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    // MARK: - Computed Properties

    var subscriptionTier: SubscriptionTier {
        guard let profile = currentProfile else { return .free }
        return SubscriptionTier(rawValue: profile.subscriptionTier) ?? .free
    }

    var hasCompletedOnboarding: Bool {
        currentProfile?.hasCompletedOnboarding ?? false
    }

    var isPro: Bool {
        subscriptionTier == .pro && currentProfile?.subscriptionStatus == "active"
    }
}

// MARK: - API Models

struct UserSyncRequest: Encodable {
    let displayName: String?
}

struct UpdateProfileRequest: Encodable {
    let displayName: String?
    let notificationsEnabled: Bool?
    let darkModeEnabled: Bool?
}

struct ResetJournalModeRequest: Encodable {
    let resetJournalMode: Bool
}

struct UserProfileResponse: Decodable {
    let uid: String
    let email: String?
    let displayName: String?
    let profileImageUrl: String?
    let subscriptionTier: String
    let hasCompletedOnboarding: Bool
    let subscriptionStatus: String?
    let subscriptionExpiresAt: Date?
    let journalMode: String?
    let notificationsEnabled: Bool?
    let darkModeEnabled: Bool?
    let createdAt: Date
    let updatedAt: Date
}
