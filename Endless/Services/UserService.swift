import Foundation

/// Response model for user sync endpoint
struct UserSyncResponse: Codable {
    let uid: String
    let email: String?
    let planTier: String
    let plansRemaining: Int
    let plansYear: Int
}

/// Response model for plans status endpoint
struct PlansStatusResponse: Codable {
    let planTier: String
    let plansRemaining: Int
    let plansYear: Int
}

class UserService {
    static let shared = UserService()
    private init() {}

    /// Get Firebase ID token for authenticated requests
    /// In production, this calls FirebaseAuth.auth().currentUser?.getIDToken()
    private func getFirebaseToken() async throws -> String {
        // TODO: Replace with actual Firebase Auth call
        // return try await Auth.auth().currentUser?.getIDToken() ?? ""
        print("[UserService] WARNING: Using placeholder token - implement Firebase Auth")
        return "placeholder-token"
    }

    /// Sync user with backend - creates user if new, applies yearly reset if needed
    /// Returns UserSyncResponse with plans data
    /// CRITICAL: Backend ensures new users get plansRemaining=3, NOT 0
    func syncUser() async throws -> UserSyncResponse {
        let url = URL(string: "\(Config.backendURL)/api/users/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add Firebase auth token
        let token = try await getFirebaseToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        print("[UserService] Calling /api/users/sync")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[UserService] ERROR: Invalid response type")
            throw URLError(.badServerResponse)
        }

        print("[UserService] Response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("[UserService] ERROR: Bad status code \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        let syncResponse = try JSONDecoder().decode(UserSyncResponse.self, from: data)
        print("[UserService] Sync success: plansRemaining=\(syncResponse.plansRemaining), tier=\(syncResponse.planTier)")

        return syncResponse
    }

    /// Get current plans status from backend
    func getPlansStatus() async throws -> PlansStatusResponse {
        let url = URL(string: "\(Config.backendURL)/api/users/plans")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let token = try await getFirebaseToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        print("[UserService] Calling /api/users/plans")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("[UserService] ERROR: Bad response from /api/users/plans")
            throw URLError(.badServerResponse)
        }

        let status = try JSONDecoder().decode(PlansStatusResponse.self, from: data)
        print("[UserService] Plans status: plansRemaining=\(status.plansRemaining), tier=\(status.planTier)")

        return status
    }
}
