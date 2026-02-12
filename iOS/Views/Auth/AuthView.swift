import SwiftUI
import AuthenticationServices
import CryptoKit

struct AuthView: View {

    @EnvironmentObject private var appState: AppState
    @State private var mode: AuthMode = .signIn
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentNonce: String?

    enum AuthMode {
        case signIn, signUp
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.spacingXL) {
                    Spacer(minLength: 60)

                    // App title
                    Text("CURATED")
                        .font(.system(size: 22, weight: .semibold, design: .default))
                        .tracking(4.0)
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(mode == .signIn ? "Welcome back" : "Create your account")
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.textSecondary)

                    // Form fields
                    VStack(spacing: Theme.spacingM) {
                        if mode == .signUp {
                            TextField("Username", text: $username)
                                .textFieldStyle(.plain)
                                .font(Theme.bodyFont)
                                .padding(14)
                                .background(Theme.surface)
                                .cornerRadius(Theme.radiusM)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        TextField("Email", text: $email)
                            .textFieldStyle(.plain)
                            .font(Theme.bodyFont)
                            .padding(14)
                            .background(Theme.surface)
                            .cornerRadius(Theme.radiusM)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("Password", text: $password)
                            .textFieldStyle(.plain)
                            .font(Theme.bodyFont)
                            .padding(14)
                            .background(Theme.surface)
                            .cornerRadius(Theme.radiusM)
                    }
                    .padding(.horizontal, Theme.spacingXL)

                    // Error message
                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.destructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.spacingXL)
                    }

                    // Submit button
                    Button {
                        submit()
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(mode == .signIn ? "Sign In" : "Sign Up")
                                    .font(Theme.headlineFont)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isFormValid ? Theme.accent : Theme.textTertiary)
                        .cornerRadius(Theme.radiusM)
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.horizontal, Theme.spacingXL)

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 1)
                        Text("or")
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textTertiary)
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, Theme.spacingXL)

                    // Apple Sign In
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = randomNonceString()
                        currentNonce = nonce
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = sha256(nonce)
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(Theme.radiusM)
                    .padding(.horizontal, Theme.spacingXL)
                    .disabled(isLoading)

                    // Toggle mode
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = (mode == .signIn) ? .signUp : .signIn
                            errorMessage = nil
                        }
                    } label: {
                        Text(mode == .signIn
                             ? "Don't have an account? Sign Up"
                             : "Already have an account? Sign In")
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var isFormValid: Bool {
        let hasEmail = !email.trimmingCharacters(in: .whitespaces).isEmpty
        let hasPassword = password.count >= 6
        if mode == .signUp {
            let hasUsername = !username.trimmingCharacters(in: .whitespaces).isEmpty
            return hasEmail && hasPassword && hasUsername
        }
        return hasEmail && hasPassword
    }

    private func submit() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if mode == .signIn {
                    try await appState.authService.signIn(email: email, password: password)
                } else {
                    try await appState.authService.signUp(
                        username: username.trimmingCharacters(in: .whitespaces),
                        email: email.trimmingCharacters(in: .whitespaces),
                        password: password
                    )
                }
                appState.isAuthenticated = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Apple Sign In

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = appleCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Unable to get Apple credentials."
                return
            }

            isLoading = true
            errorMessage = nil

            Task {
                do {
                    try await appState.authService.signInWithApple(
                        identityToken: identityToken,
                        nonce: nonce
                    )
                    appState.isAuthenticated = true
                } catch {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }

        case .failure(let error):
            // Don't show error if user cancelled
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(errorCode == errSecSuccess)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
