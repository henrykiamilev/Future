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
        let response: AuthResponse = try await client.request(
            APIEndpoint(path: "/auth/signin", method: .POST, body: AuthRequest(email: email, password: password))
        )
        tokenProvider.store(token: response.accessToken)
    }

    func signUp(username: String, email: String, password: String) async throws {
        let response: AuthResponse = try await client.request(
            APIEndpoint(path: "/auth/signup", method: .POST, body: SignUpRequest(username: username, email: email, password: password))
        )
        tokenProvider.store(token: response.accessToken)
    }

    func signOut() {
        tokenProvider.clear()
    }

    private func extractUserID(from token: String) -> UUID? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2,
              let data = Data(base64Encoded: String(segments[1])
                  .padding(toLength: ((String(segments[1]).count + 3) / 4) * 4, withPad: "=", startingAt: 0)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        return UUID(uuidString: sub)
    }
}

private struct AuthRequest: Encodable, Sendable {
    let email: String
    let password: String
}

private struct SignUpRequest: Encodable, Sendable {
    let username: String
    let email: String
    let password: String
}

private struct AuthResponse: Decodable, Sendable {
    let accessToken: String
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case accessToken
        case userID = "userId"
    }
}
