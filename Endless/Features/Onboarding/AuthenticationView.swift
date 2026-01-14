import SwiftUI

/// Authentication screen with Sign In and Create Account options.
/// Clean, minimal design with no clutter or distractions.
struct AuthenticationView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var authMode: AuthMode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                // Header
                headerSection

                // Mode toggle
                authModeToggle

                // Form fields
                formSection

                // Primary action button
                primaryButton

                // Divider
                dividerSection

                // Social sign in
                socialSignInSection

                Spacer(minLength: Theme.Spacing.xxl)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xxl)
        }
        .background(Theme.Colors.background(for: colorScheme))
        .onTapGesture {
            hideKeyboard()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Small infinity logo
            InfinityShape()
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 48, height: 24)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

            Text("Endless")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

            Text(authMode == .signIn ? "Welcome back" : "Start your journey")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                .padding(.top, Theme.Spacing.xxs)
        }
    }

    // MARK: - Auth Mode Toggle

    private var authModeToggle: some View {
        HStack(spacing: 0) {
            toggleButton(title: "Sign In", mode: .signIn)
            toggleButton(title: "Create Account", mode: .createAccount)
        }
        .background(Theme.Colors.backgroundSecondary(for: colorScheme))
        .cornerRadius(Theme.Radius.md)
        .padding(.top, Theme.Spacing.md)
    }

    private func toggleButton(title: String, mode: AuthMode) -> some View {
        Button {
            withAnimation(Theme.Animation.quick) {
                authMode = mode
                errorMessage = nil
            }
        } label: {
            Text(title)
                .font(Theme.Typography.subheadline)
                .foregroundColor(authMode == mode
                    ? Theme.Colors.textPrimary(for: colorScheme)
                    : Theme.Colors.textSecondary(for: colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(authMode == mode
                    ? Theme.Colors.background(for: colorScheme)
                    : Color.clear)
                .cornerRadius(Theme.Radius.sm)
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.xxs)
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Email field
            AuthTextField(
                placeholder: "Email",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress
            )

            // Password field
            AuthSecureField(
                placeholder: "Password",
                text: $password,
                textContentType: authMode == .signIn ? .password : .newPassword
            )

            // Confirm password (create account only)
            if authMode == .createAccount {
                AuthSecureField(
                    placeholder: "Confirm Password",
                    text: $confirmPassword,
                    textContentType: .newPassword
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Color(hex: "E55050"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Animation.standard, value: authMode)
    }

    // MARK: - Primary Button

    private var primaryButton: some View {
        Button {
            performAuth()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(authMode == .signIn ? "Sign In" : "Create Account")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading || !isFormValid)
        .opacity(isFormValid ? 1 : 0.6)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Divider

    private var dividerSection: some View {
        HStack(spacing: Theme.Spacing.md) {
            Rectangle()
                .fill(Theme.Colors.textTertiary(for: colorScheme))
                .frame(height: 1)

            Text("or")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            Rectangle()
                .fill(Theme.Colors.textTertiary(for: colorScheme))
                .frame(height: 1)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Social Sign In

    private var socialSignInSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Google Sign In (preferred per PRD)
            SocialSignInButton(
                provider: .google,
                action: { performGoogleSignIn() }
            )

            // Apple Sign In
            SocialSignInButton(
                provider: .apple,
                action: { performAppleSignIn() }
            )
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 8

        if authMode == .signIn {
            return emailValid && passwordValid
        } else {
            return emailValid && passwordValid && password == confirmPassword
        }
    }

    // MARK: - Actions

    private func performAuth() {
        hideKeyboard()
        errorMessage = nil
        isLoading = true

        Task {
            do {
                if authMode == .signIn {
                    try await AuthService.shared.signIn(email: email, password: password)
                } else {
                    try await AuthService.shared.createAccount(email: email, password: password)
                }

                // Sync user profile with backend (creates if new, updates if existing)
                _ = try await UserService.shared.syncUser()

                // Refresh token status for AI features
                await AIService.shared.refreshTokenStatus()

                isLoading = false
                appState.completeAuthentication()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performGoogleSignIn() {
        // Google Sign In requires additional SDK setup
        // For now, show a message that it's not yet configured
        errorMessage = "Google Sign In requires additional configuration"
    }

    private func performAppleSignIn() {
        // Apple Sign In will be triggered via SignInWithAppleButton
        // For now, show a message
        errorMessage = "Apple Sign In requires additional configuration"
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Auth Mode

enum AuthMode {
    case signIn
    case createAccount
}

// MARK: - Auth Text Field

struct AuthTextField: View {
    @Environment(\.colorScheme) private var colorScheme

    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil

    var body: some View {
        TextField(placeholder, text: $text)
            .font(Theme.Typography.body)
            .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundSecondary(for: colorScheme))
            .cornerRadius(Theme.Radius.md)
    }
}

// MARK: - Auth Secure Field

struct AuthSecureField: View {
    @Environment(\.colorScheme) private var colorScheme

    let placeholder: String
    @Binding var text: String
    var textContentType: UITextContentType? = nil

    @State private var isSecured: Bool = true

    var body: some View {
        HStack {
            Group {
                if isSecured {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(Theme.Typography.body)
            .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
            .textContentType(textContentType)
            .autocapitalization(.none)
            .disableAutocorrection(true)

            Button {
                isSecured.toggle()
            } label: {
                Image(systemName: isSecured ? "eye.slash" : "eye")
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                    .font(.system(size: 16))
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundSecondary(for: colorScheme))
        .cornerRadius(Theme.Radius.md)
    }
}

// MARK: - Social Sign In Button

struct SocialSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let provider: SocialProvider
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 18))

                Text(provider.title)
                    .font(Theme.Typography.headline)
            }
            .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.backgroundSecondary(for: colorScheme))
            .cornerRadius(Theme.Radius.md)
        }
        .buttonStyle(.plain)
    }
}

enum SocialProvider {
    case google
    case apple

    var title: String {
        switch self {
        case .google: return "Continue with Google"
        case .apple: return "Continue with Apple"
        }
    }

    var iconName: String {
        switch self {
        case .google: return "globe" // Placeholder, actual Google icon via asset
        case .apple: return "apple.logo"
        }
    }
}

// MARK: - Preview

#Preview("Auth - Light") {
    AuthenticationView()
        .environmentObject(AppState())
        .preferredColorScheme(.light)
}

#Preview("Auth - Dark") {
    AuthenticationView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
