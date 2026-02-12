import Foundation

protocol AuthServiceProtocol: Sendable {
    var isAuthenticated: Bool { get }
    var currentUserID: UUID? { get }
    func signIn(email: String, password: String) async throws
    func signUp(username: String, email: String, password: String) async throws
    func signOut()
}

final class AuthService: AuthServiceProtocol, Sendable {

    private let client: APIClientProtocol
    private let tokenProvider: KeychainTokenProvider

    var isAuthenticated: Bool { tokenProvider.currentToken != nil }
    var currentUserID: UUID? {
        guard let token = tokenProvider.currentToken else { return nil }
        return extractUserID(from: token)
    }

    init(client: APIClientProtocol, tokenProvider: KeychainTokenProvider) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func signIn(email: String, password: String) async throws {
        // Supabase Auth: POST /auth/v1/token?grant_type=password
        let response: SupabaseAuthResponse = try await client.request(
            APIEndpoint(
                path: "/auth/v1/token",
                method: .POST,
                queryItems: [.init(name: "grant_type", value: "password")],
                body: SupabaseSignIn(email: email, password: password)
            )
        )
        tokenProvider.store(token: response.accessToken)
        tokenProvider.storeRefreshToken(response.refreshToken)
    }

    func signUp(username: String, email: String, password: String) async throws {
        // Supabase Auth: POST /auth/v1/signup
        // Pass username in user_metadata so we can use it in the trigger/hook
        let response: SupabaseAuthResponse = try await client.request(
            APIEndpoint(
                path: "/auth/v1/signup",
                method: .POST,
                body: SupabaseSignUp(
                    email: email,
                    password: password,
                    data: UserMetadata(username: username)
                )
            )
        )
        tokenProvider.store(token: response.accessToken)
        tokenProvider.storeRefreshToken(response.refreshToken)

        // Create the user row in our users table (Supabase Auth creates
        // auth.users, but we need a row in public.users for our schema).
        // This is typically handled by a Supabase database trigger on
        // auth.users INSERT, but we also call it explicitly as a fallback.
        try? await client.requestVoid(
            APIEndpoint(
                path: "/rest/v1/users",
                method: .POST,
                body: CreateUserRow(
                    id: response.user.id,
                    username: username
                )
            )
        )
    }

    func signOut() {
        tokenProvider.clear()
        NotificationCenter.default.post(name: .authSessionExpired, object: nil)
    }

    private func extractUserID(from token: String) -> UUID? {
        // Decode JWT payload to extract Supabase 'sub' claim
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        return UUID(uuidString: sub)
    }
}

// MARK: - Supabase Auth Types

private struct SupabaseSignIn: Encodable, Sendable {
    let email: String
    let password: String
}

private struct SupabaseSignUp: Encodable, Sendable {
    let email: String
    let password: String
    let data: UserMetadata
}

private struct UserMetadata: Encodable, Sendable {
    let username: String
}

private struct SupabaseAuthResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let user: SupabaseUser
}

private struct SupabaseUser: Decodable, Sendable {
    let id: UUID
    let email: String?
}

private struct CreateUserRow: Encodable, Sendable {
    let id: UUID
    let username: String
}
