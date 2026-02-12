import SwiftUI

struct AuthView: View {

    @EnvironmentObject private var appState: AppState
    @State private var mode: AuthMode = .signIn
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum AuthMode {
        case signIn, signUp
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: Theme.spacingXL) {
                Spacer()

                // App title
                Text("CURATED")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .tracking(4.0)
                    .foregroundColor(Theme.textPrimary)

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

                Spacer()
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
}
