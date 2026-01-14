import Foundation
import UIKit

// MARK: - Subscription Service

/// Service for subscription management via backend API.
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published private(set) var subscriptionStatus: SubscriptionStatusResponse?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Public Methods

    /// Create a Stripe checkout session and open in Safari.
    func startCheckout(priceType: PriceType) async throws {
        isLoading = true
        error = nil

        do {
            let request = CheckoutRequest(priceType: priceType)
            let response: CheckoutResponse = try await apiClient.post("/subscriptions/checkout", body: request)

            // Open checkout URL in Safari
            if let url = URL(string: response.checkoutUrl) {
                await UIApplication.shared.open(url)
            }

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Get current subscription status.
    func getStatus() async throws -> SubscriptionStatusResponse {
        isLoading = true
        error = nil

        do {
            let response: SubscriptionStatusResponse = try await apiClient.get("/subscriptions/status")
            subscriptionStatus = response
            isLoading = false
            return response
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Open Stripe customer portal for subscription management.
    func openCustomerPortal() async throws {
        isLoading = true
        error = nil

        do {
            let response: PortalResponse = try await apiClient.post(
                "/subscriptions/portal",
                body: EmptyRequest()
            )

            // Open portal URL in Safari
            if let url = URL(string: response.portalUrl) {
                await UIApplication.shared.open(url)
            }

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Refresh subscription status silently.
    func refreshStatus() async {
        do {
            _ = try await getStatus()
        } catch {
            print("[SubscriptionService] Status refresh failed: \(error)")
        }
    }

    // MARK: - Computed Properties

    var isPro: Bool {
        subscriptionStatus?.isActive ?? false
    }

    var tier: String {
        subscriptionStatus?.tier ?? "free"
    }
}

// MARK: - Price Type

enum PriceType: String, Encodable {
    case monthly
    case yearly
}

// MARK: - API Models

struct CheckoutRequest: Encodable {
    let priceType: PriceType
}

struct CheckoutResponse: Decodable {
    let checkoutUrl: String
    let sessionId: String
}

struct SubscriptionStatusResponse: Decodable {
    let tier: String
    let status: String?
    let expiresAt: Date?
    let isActive: Bool
}

struct PortalResponse: Decodable {
    let portalUrl: String
}

struct EmptyRequest: Encodable {}
