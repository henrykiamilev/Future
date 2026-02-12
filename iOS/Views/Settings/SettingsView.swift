import SwiftUI

struct SettingsView: View {

    @StateObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    let profile: UserProfile

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.spacingXL) {
                    avatarHeader
                    profileFieldsCard
                    socialLinksCard
                    accountCard
                    dangerZone
                }
                .padding(.horizontal, Theme.spacingL)
                .padding(.top, Theme.spacingL)
                .padding(.bottom, Theme.spacingXXL)
            }
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.textSecondary)
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
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .confirmationDialog(
                "Delete Account",
                isPresented: $viewModel.showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await viewModel.deleteAccount() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action is permanent and cannot be undone.")
            }
            .onAppear {
                viewModel.loadFrom(profile: profile)
            }
            .onChange(of: viewModel.didSignOut) { _, newValue in
                if newValue { dismiss() }
            }
        }
    }

    // MARK: - Avatar Header

    private var avatarHeader: some View {
        VStack(spacing: Theme.spacingS) {
            AsyncImage(url: URL(string: profile.user.profilePhotoURL ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            Text("@\(profile.user.username)")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.spacingS)
    }

    // MARK: - Profile Fields Card

    private var profileFieldsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader("Profile")

            VStack(spacing: 0) {
                fieldRow(label: "Display name", text: $viewModel.displayName)

                Divider()
                    .background(Theme.separator)

                bioRow
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusL)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
            }
        }
    }

    // MARK: - Social Links Card

    private var socialLinksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader("Social Links")

            VStack(spacing: 0) {
                socialFieldRow(
                    icon: "camera.fill",
                    placeholder: "Instagram username",
                    text: $viewModel.instagramHandle
                )

                Divider()
                    .background(Theme.separator)

                socialFieldRow(
                    icon: "message.fill",
                    placeholder: "Snapchat username",
                    text: $viewModel.snapchatHandle
                )
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusL)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
            }

            Text("Tapping your handle on your profile will open the app directly.")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
                .padding(.top, Theme.spacingS)
                .padding(.horizontal, Theme.spacingXS)
        }
    }

    // MARK: - Account Card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader("Account")

            VStack(spacing: 0) {
                HStack {
                    Text("Account visibility")
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.textPrimary)

                    Spacer()

                    Button {
                        Task { await viewModel.toggleVisibility() }
                    } label: {
                        HStack(spacing: Theme.spacingXS) {
                            Text(viewModel.visibility == .public ? "Public" : "Private")
                                .font(Theme.headlineFont)

                            Image(systemName: viewModel.visibility == .public ? "globe" : "lock.fill")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(Theme.accent)
                    }
                }
                .padding(.horizontal, Theme.spacingM)
                .padding(.vertical, 14)

                Divider()
                    .background(Theme.separator)

                Button {
                    viewModel.signOut()
                } label: {
                    HStack {
                        Text("Sign Out")
                            .font(Theme.bodyFont)
                            .foregroundColor(Theme.textPrimary)

                        Spacer()

                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.vertical, 14)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusL)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
            }
        }
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        Button {
            viewModel.showDeleteConfirmation = true
        } label: {
            HStack {
                Text("Delete Account")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.destructive)

                Spacer()

                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.destructive.opacity(0.6))
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusL)
                    .strokeBorder(Theme.destructive.opacity(0.15), lineWidth: 1)
            }
        }
    }

    // MARK: - Reusable Components

    private func cardHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.sectionHeaderFont)
            .foregroundColor(Theme.textTertiary)
            .tracking(1.2)
            .padding(.horizontal, Theme.spacingXS)
            .padding(.bottom, Theme.spacingS)
    }

    private func fieldRow(label: String, text: Binding<String>) -> some View {
        HStack(spacing: Theme.spacingS) {
            Text(label)
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
                .frame(width: 90, alignment: .leading)

            TextField("", text: text)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, 14)
    }

    private var bioRow: some View {
        HStack(alignment: .top, spacing: Theme.spacingS) {
            Text("Bio")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
                .frame(width: 90, alignment: .leading)
                .padding(.top, 2)

            TextField("Write something about yourself", text: $viewModel.bio, axis: .vertical)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(3...6)
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, 14)
    }

    private func socialFieldRow(
        icon: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 24)

            TextField(placeholder, text: text)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, 14)
    }
}
