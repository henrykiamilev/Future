import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(action: performSignIn) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Sign In")
                }
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
        }
        .padding()
    }

    private func performSignIn() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                // Firebase authentication would happen here
                try await authenticateWithFirebase()

                // CRITICAL: Complete authentication BEFORE backend sync
                isLoading = false
                appState.completeAuthentication()

                // Backend sync is non-blocking - failures do NOT block UI
                Task {
                    do {
                        _ = try await UserService.shared.syncUser()
                        await AIService.shared.refreshTokenStatus()
                    } catch {
                        print("[Auth] Backend sync failed (non-fatal): \(error.localizedDescription)")
                    }
                }
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func authenticateWithFirebase() async throws {
        // Firebase Auth implementation placeholder
        // In production, this calls Firebase Auth SDK
    }
}
