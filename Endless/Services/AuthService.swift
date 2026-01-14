import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit

// MARK: - Auth Service

/// Service for Firebase authentication.
/// Handles sign in, sign out, and token management.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var currentUser: User?
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    /// Current nonce for Apple Sign In (stored for verification)
    private var currentNonce: String?

    private init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil

                // Set up token provider for API client
                if user != nil {
                    APIClient.shared.tokenProvider = { [weak self] in
                        try await self?.getIDToken() ?? ""
                    }
                } else {
                    APIClient.shared.tokenProvider = nil
                }
            }
        }
    }

    // MARK: - Token Management

    /// Get current user's Firebase ID token for API authentication.
    func getIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        return try await user.getIDToken()
    }

    // MARK: - Email/Password Authentication

    /// Sign in with email and password.
    func signIn(email: String, password: String) async throws {
        isLoading = true
        error = nil

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentUser = result.user
            isAuthenticated = true
        } catch {
            self.error = error
            throw AuthError.signInFailed(error)
        }

        isLoading = false
    }

    /// Create account with email and password.
    func createAccount(email: String, password: String) async throws {
        isLoading = true
        error = nil

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            currentUser = result.user
            isAuthenticated = true
        } catch {
            self.error = error
            throw AuthError.accountCreationFailed(error)
        }

        isLoading = false
    }

    // MARK: - Google Sign In

    /// Sign in with Google.
    /// Note: Requires GoogleSignIn SDK configuration.
    func signInWithGoogle(presentingViewController: Any) async throws {
        // Google Sign In implementation requires GoogleSignIn SDK
        // This is a placeholder - actual implementation needs:
        // 1. GIDSignIn.sharedInstance.signIn(withPresenting:)
        // 2. Convert Google credential to Firebase credential
        // 3. Sign in with Firebase
        throw AuthError.notImplemented
    }

    // MARK: - Apple Sign In

    /// Prepare Apple Sign In request.
    func prepareAppleSignInRequest() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        return request
    }

    /// Complete Apple Sign In with authorization result.
    func completeAppleSignIn(authorization: ASAuthorization) async throws {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }

        guard let nonce = currentNonce else {
            throw AuthError.invalidNonce
        }

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.invalidToken
        }

        isLoading = true
        error = nil

        do {
            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            let result = try await Auth.auth().signIn(with: credential)
            currentUser = result.user
            isAuthenticated = true
        } catch {
            self.error = error
            throw AuthError.signInFailed(error)
        }

        isLoading = false
    }

    // MARK: - Sign Out

    /// Sign out current user.
    func signOut() throws {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            self.error = error
            throw AuthError.signOutFailed(error)
        }
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Auth Error

enum AuthError: Error, LocalizedError {
    case notAuthenticated
    case signInFailed(Error)
    case accountCreationFailed(Error)
    case signOutFailed(Error)
    case invalidCredential
    case invalidNonce
    case invalidToken
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .signInFailed(let error):
            return "Sign in failed: \(error.localizedDescription)"
        case .accountCreationFailed(let error):
            return "Account creation failed: \(error.localizedDescription)"
        case .signOutFailed(let error):
            return "Sign out failed: \(error.localizedDescription)"
        case .invalidCredential:
            return "Invalid credential"
        case .invalidNonce:
            return "Invalid nonce"
        case .invalidToken:
            return "Invalid token"
        case .notImplemented:
            return "This feature is not yet implemented"
        }
    }
}
