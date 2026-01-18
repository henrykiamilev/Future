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
                        print("[Auth] Starting backend sync...")
                        let syncResponse = try await UserService.shared.syncUser()

                        // Update AppState with plans data from backend
                        // CRITICAL: Backend returns plansRemaining=3 for new users, NOT 0
                        await MainActor.run {
                            print("[Auth] Updating AppState: plansRemaining=\(syncResponse.plansRemaining)")
                            appState.updatePlansStatus(
                                remaining: syncResponse.plansRemaining,
                                tier: syncResponse.planTier,
                                year: syncResponse.plansYear
                            )
                        }

                        await AIService.shared.refreshTokenStatus()
                        print("[Auth] Backend sync completed successfully")
                    } catch {
                        // Backend failure is non-fatal - user can still use app
                        // AppState.displayPlansRemaining returns tier limit when nil
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
