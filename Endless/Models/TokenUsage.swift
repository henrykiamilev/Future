import Foundation

// MARK: - Token Usage

struct TokenUsage: Codable, Identifiable {
    let id: String
    let userId: String

    // Usage tracking
    var lifetimeUsed: Int
    var currentYearUsed: Int
    var yearStartDate: Date?

    // Metadata
    var lastUsedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        lifetimeUsed: Int = 0,
        currentYearUsed: Int = 0,
        yearStartDate: Date? = nil,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.lifetimeUsed = lifetimeUsed
        self.currentYearUsed = currentYearUsed
        self.yearStartDate = yearStartDate
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Token Limits

enum TokenLimits {
    static let freeLifetimeLimit = 3
    static let proYearlyLimit = 52
}

// MARK: - Convenience

extension TokenUsage {
    /// Check if user can generate a new AI plan based on their subscription tier
    func canGenerate(tier: SubscriptionTier) -> Bool {
        switch tier {
        case .free:
            return lifetimeUsed < TokenLimits.freeLifetimeLimit
        case .pro:
            return currentYearUsed < TokenLimits.proYearlyLimit
        }
    }

    /// Returns remaining tokens based on subscription tier
    func remainingTokens(tier: SubscriptionTier) -> Int {
        switch tier {
        case .free:
            return max(0, TokenLimits.freeLifetimeLimit - lifetimeUsed)
        case .pro:
            return max(0, TokenLimits.proYearlyLimit - currentYearUsed)
        }
    }

    /// Returns a new TokenUsage with incremented count
    func incrementing(tier: SubscriptionTier) -> TokenUsage {
        var updated = self
        updated.lifetimeUsed += 1
        if tier == .pro {
            updated.currentYearUsed += 1
        }
        updated.lastUsedAt = Date()
        updated.updatedAt = Date()
        return updated
    }

    /// Check if yearly counter needs reset (for Pro users)
    func needsYearlyReset() -> Bool {
        guard let yearStart = yearStartDate else { return true }
        let calendar = Calendar.current
        let yearsSinceStart = calendar.dateComponents([.year], from: yearStart, to: Date()).year ?? 0
        return yearsSinceStart >= 1
    }

    /// Returns a new TokenUsage with reset yearly counter
    func resettingYearlyCounter() -> TokenUsage {
        var updated = self
        updated.currentYearUsed = 0
        updated.yearStartDate = Date()
        updated.updatedAt = Date()
        return updated
    }
}
