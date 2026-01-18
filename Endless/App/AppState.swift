import Foundation
import SwiftUI

/// Plan tier limits - MUST match backend
enum PlanTier: String {
    case free = "free"
    case pro = "pro"

    var planLimit: Int {
        switch self {
        case .free: return 3
        case .pro: return 200
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false

    // CRITICAL: Plans tracking with proper defaults
    // plansRemaining is Optional - nil means "not yet loaded from server"
    // nil must NEVER be treated as 0
    @Published private(set) var plansRemaining: Int?
    @Published private(set) var planTier: PlanTier = .free
    @Published private(set) var plansYear: Int?

    /// Computed property that returns display value
    /// CRITICAL: If nil, returns tier limit (NOT 0)
    var displayPlansRemaining: Int {
        if let remaining = plansRemaining {
            return remaining
        }
        // Not loaded yet - show tier default, NOT 0
        print("[AppState] plansRemaining is nil, returning tier limit: \(planTier.planLimit)")
        return planTier.planLimit
    }

    func completeAuthentication() {
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        // Reset plans state on sign out
        plansRemaining = nil
        planTier = .free
        plansYear = nil
    }

    /// Update plans status from backend response
    /// CRITICAL: Only updates if value is valid (not nil from backend)
    func updatePlansStatus(remaining: Int?, tier: String?, year: Int?) {
        print("[AppState] updatePlansStatus called: remaining=\(String(describing: remaining)), tier=\(String(describing: tier)), year=\(String(describing: year))")

        // CRITICAL: Only update plansRemaining if backend returned a valid value
        // Never overwrite with nil or 0 unless explicitly returned
        if let remaining = remaining {
            // Additional safety: never set to negative
            self.plansRemaining = max(0, remaining)
            print("[AppState] Set plansRemaining to \(self.plansRemaining!)")
        } else {
            print("[AppState] WARNING: Backend returned nil for plansRemaining, keeping current value")
        }

        if let tierString = tier, let newTier = PlanTier(rawValue: tierString) {
            self.planTier = newTier
        }

        if let year = year {
            self.plansYear = year
        }
    }

    /// Decrement plans after successful generation (local update)
    /// Backend is source of truth, but we update locally for UI responsiveness
    func decrementPlans() {
        guard let current = plansRemaining, current > 0 else {
            print("[AppState] Cannot decrement: plansRemaining is nil or 0")
            return
        }
        plansRemaining = current - 1
        print("[AppState] Decremented plansRemaining to \(plansRemaining!)")
    }
}
