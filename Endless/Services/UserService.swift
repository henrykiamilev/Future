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

struct UserProfileResponse: Decodable {
    let uid: String
    let email: String?
    let displayName: String?
    let subscriptionTier: String
    let hasCompletedOnboarding: Bool
    let subscriptionStatus: String?
    let subscriptionExpiresAt: Date?
    let createdAt: Date
    let updatedAt: Date
}
