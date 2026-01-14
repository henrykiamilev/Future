import Foundation

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable {
    case free
    case pro
}

// MARK: - User Profile

struct UserProfile: Codable, Identifiable {
    let id: String
    var email: String
    var displayName: String?
    var profileImageURL: URL?

    // Subscription
    var subscriptionTier: SubscriptionTier
    var subscriptionExpiresAt: Date?

    // Onboarding state
    var hasCompletedOnboarding: Bool
    var onboardingCompletedAt: Date?

    // Preferences
    var journalMode: JournalMode?
    var notificationsEnabled: Bool
    var darkModeEnabled: Bool?

    // Metadata
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        email: String,
        displayName: String? = nil,
        profileImageURL: URL? = nil,
        subscriptionTier: SubscriptionTier = .free,
        subscriptionExpiresAt: Date? = nil,
        hasCompletedOnboarding: Bool = false,
        onboardingCompletedAt: Date? = nil,
        journalMode: JournalMode? = nil,
        notificationsEnabled: Bool = true,
        darkModeEnabled: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.subscriptionTier = subscriptionTier
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.onboardingCompletedAt = onboardingCompletedAt
        self.journalMode = journalMode
        self.notificationsEnabled = notificationsEnabled
        self.darkModeEnabled = darkModeEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Journal Mode

enum JournalMode: String, Codable {
    case freeText
    case guidedPrompts
}

// MARK: - Convenience

extension UserProfile {
    var isPro: Bool {
        guard subscriptionTier == .pro else { return false }
        if let expiresAt = subscriptionExpiresAt {
            return expiresAt > Date()
        }
        return false
    }

    var needsOnboarding: Bool {
        !hasCompletedOnboarding
    }
}
