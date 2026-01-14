import Foundation

// MARK: - AI Service

/// Service for AI plan generation via backend API.
@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var lastGeneratedPlan: AIGenerateResponse?
    @Published private(set) var tokenStatus: TokenStatusResponse?
    @Published private(set) var error: Error?

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Public Methods

    /// Generate a new AI plan based on user's goal text.
    /// Consumes one token on success.
    func generatePlan(goalText: String) async throws -> AIGenerateResponse {
        isGenerating = true
        error = nil

        do {
            let request = AIGenerateRequest(goalText: goalText)
            let response: AIGenerateResponse = try await apiClient.post(
                "/ai/generate",
                body: request,
                timeout: Config.aiGenerationTimeout
            )
            lastGeneratedPlan = response
            isGenerating = false
            return response
        } catch let apiError as APIError {
            self.error = apiError
            isGenerating = false

            // Check if it's a token limit error
            if case .forbidden(let message) = apiError {
                throw AIServiceError.noTokensRemaining(message)
            }
            throw apiError
        } catch {
            self.error = error
            isGenerating = false
            throw error
        }
    }

    /// Get current token status (remaining tokens, limit, tier).
    func getTokenStatus() async throws -> TokenStatusResponse {
        do {
            let response: TokenStatusResponse = try await apiClient.get("/ai/tokens")
            tokenStatus = response
            return response
        } catch {
            self.error = error
            throw error
        }
    }

    /// Refresh token status silently.
    func refreshTokenStatus() async {
        do {
            _ = try await getTokenStatus()
        } catch {
            print("[AIService] Token status refresh failed: \(error)")
        }
    }

    // MARK: - Computed Properties

    var remainingTokens: Int {
        tokenStatus?.remaining ?? 0
    }

    var canGenerate: Bool {
        remainingTokens > 0
    }
}

// MARK: - AI Service Error

enum AIServiceError: Error, LocalizedError {
    case noTokensRemaining(String)

    var errorDescription: String? {
        switch self {
        case .noTokensRemaining(let message):
            return message
        }
    }
}

// MARK: - API Models

struct AIGenerateRequest: Encodable {
    let goalText: String
}

struct AIGenerateResponse: Decodable {
    let planId: String
    let summary: String
    let items: [GeneratedItem]
    let eventsCreated: Int
    let tasksCreated: Int
    let tokensRemaining: Int
}

struct GeneratedItem: Decodable, Identifiable {
    let id: String
    let type: String
    let title: String
    let scheduledDate: String?
    let scheduledTime: String?
    let endTime: String?
    let estimatedMinutes: Int?
    let isFlexible: Bool
    let purpose: String
    let explanation: String
    let category: String?
    let priority: String?
}

struct TokenStatusResponse: Decodable {
    let remaining: Int
    let limit: Int
    let tier: String
}
