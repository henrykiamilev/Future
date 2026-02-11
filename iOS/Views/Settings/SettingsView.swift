import SwiftUI

struct SettingsView: View {

    @StateObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    let profile: UserProfile

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                socialLinksSection
                accountSection
                dangerSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView().tint(Theme.textTertiary)
                    } else {
                        Button("Save") {
                            Task {
                                await viewModel.saveProfile()
                                dismiss()
                            }
                        }
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.accent)
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") { }
            } message: {
                Text(viewModel.error ?? "")
            }
            .confirmationDialog(
                "Delete Account",
                isPresented: $viewModel.showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) { }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action is permanent and cannot be undone.")
            }
            .onAppear {
                viewModel.loadFrom(profile: profile)
            }
            .onChange(of: viewModel.didSignOut) { didSignOut in
                if didSignOut { dismiss() }
            }
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            TextField("Display name", text: $viewModel.displayName)
                .font(Theme.bodyFont)

            TextField("Bio", text: $viewModel.bio, axis: .vertical)
                .font(Theme.bodyFont)
                .lineLimit(3...6)
        } header: {
            Text("Profile")
                .font(Theme.sectionHeaderFont)
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - Social Links
    // PRD: Instagram handle, Snapchat handle. Deep link to app, fallback to web.

    private var socialLinksSection: some View {
        Section {
            HStack(spacing: Theme.spacingS) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 24)

                TextField("Instagram username", text: $viewModel.instagramHandle)
                    .font(Theme.bodyFont)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            HStack(spacing: Theme.spacingS) {
                Image(systemName: "message.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 24)

                TextField("Snapchat username", text: $viewModel.snapchatHandle)
                    .font(Theme.bodyFont)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Social Links")
                .font(Theme.sectionHeaderFont)
                .foregroundColor(Theme.textTertiary)
        } footer: {
            Text("Tapping your handle on your profile will open the app directly.")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            HStack {
                Text("Account visibility")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Button {
                    Task { await viewModel.toggleVisibility() }
                } label: {
                    Text(viewModel.visibility == .public ? "Public" : "Private")
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.accent)
                }
            }

            Button {
                viewModel.signOut()
            } label: {
                Text("Sign Out")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textPrimary)
            }
        } header: {
            Text("Account")
                .font(Theme.sectionHeaderFont)
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        Section {
            Button {
                viewModel.showDeleteConfirmation = true
            } label: {
                Text("Delete Account")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.destructive)
            }
        }
    }
}
