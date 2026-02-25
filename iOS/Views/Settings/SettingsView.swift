import SwiftUI
import PhotosUI

struct SettingsView: View {

    @StateObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    let profile: UserProfile
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    avatarHeader
                    profileSection
                    socialSection
                    preferencesSection
                    accountSection
                }
                .padding(.top, 8)
                .padding(.bottom, 60)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.custom("OpenSauceSans-SemiBold", size: 16))
                        .foregroundColor(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView().tint(Theme.textTertiary)
                    } else {
                        Button {
                            Task {
                                await viewModel.saveProfile()
                                if viewModel.error == nil {
                                    dismiss()
                                }
                            }
                        } label: {
                            Text("Done")
                                .font(.custom("OpenSauceSans-SemiBold", size: 15))
                                .foregroundColor(Theme.textPrimary)
                        }
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
        VStack(spacing: 14) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack {
                    CachedImageView(
                        url: SupabaseConfig.storageURL(for: viewModel.profilePhotoURL ?? ""),
                        targetSize: CGSize(width: 180, height: 180)
                    ) {
                        Circle()
                            .fill(Color(red: 0.92, green: 0.92, blue: 0.91))
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(Theme.textTertiary)
                            }
                    }
                    .frame(width: 90, height: 90)
                    .clipShape(Circle())

                    if viewModel.isUploadingPhoto {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 90, height: 90)
                            .overlay {
                                ProgressView().tint(.white)
                            }
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await viewModel.uploadProfilePhoto(image)
                    }
                }
            }

            VStack(spacing: 4) {
                Text("@\(profile.username)")
                    .font(.custom("OpenSauceSans-Medium", size: 15))
                    .foregroundColor(Theme.textPrimary)

                Text("Change photo")
                    .font(.custom("OpenSauceSans-Regular", size: 13))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Profile")

            VStack(spacing: 0) {
                // Display name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Display name")
                        .font(.custom("OpenSauceSans-Regular", size: 12))
                        .foregroundColor(Theme.textTertiary)

                    TextField("Your name", text: $viewModel.displayName)
                        .font(.custom("OpenSauceSans-Regular", size: 15))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                sectionDivider

                // Bio
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bio")
                        .font(.custom("OpenSauceSans-Regular", size: 12))
                        .foregroundColor(Theme.textTertiary)

                    TextField("Write something about yourself", text: $viewModel.bio, axis: .vertical)
                        .font(.custom("OpenSauceSans-Regular", size: 15))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(3...6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Social Section

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Social Links")

            VStack(spacing: 0) {
                // Instagram
                HStack(spacing: 12) {
                    Image("instagram_icon")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .opacity(0.6)
                        // Fallback if custom image not available
                        .overlay {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textTertiary)
                                .opacity(UIImage(named: "instagram_icon") == nil ? 1 : 0)
                        }

                    TextField("Instagram username", text: $viewModel.instagramHandle)
                        .font(.custom("OpenSauceSans-Regular", size: 15))
                        .foregroundColor(Theme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                sectionDivider

                // Snapchat
                HStack(spacing: 12) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 20, height: 20)

                    TextField("Snapchat username", text: $viewModel.snapchatHandle)
                        .font(.custom("OpenSauceSans-Regular", size: 15))
                        .foregroundColor(Theme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text("Tapping your handle on your profile opens the app directly.")
                .font(.custom("OpenSauceSans-Regular", size: 12))
                .foregroundColor(Theme.textTertiary)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Preferences")

            VStack(spacing: 0) {
                // Comments toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow comments")
                            .font(.custom("OpenSauceSans-Regular", size: 15))
                            .foregroundColor(Theme.textPrimary)

                        Text("Let others comment on your posts")
                            .font(.custom("OpenSauceSans-Regular", size: 12))
                            .foregroundColor(Theme.textTertiary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { viewModel.commentsEnabled },
                        set: { _ in Task { await viewModel.toggleComments() } }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: Theme.textPrimary))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                sectionDivider

                // Visibility
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private account")
                            .font(.custom("OpenSauceSans-Regular", size: 15))
                            .foregroundColor(Theme.textPrimary)

                        Text("Only approved followers can see your posts")
                            .font(.custom("OpenSauceSans-Regular", size: 12))
                            .foregroundColor(Theme.textTertiary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { viewModel.visibility == .private },
                        set: { _ in Task { await viewModel.toggleVisibility() } }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: Theme.textPrimary))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Account")

            VStack(spacing: 0) {
                // Sign out
                Button {
                    viewModel.signOut()
                } label: {
                    HStack {
                        Text("Sign Out")
                            .font(.custom("OpenSauceSans-Regular", size: 15))
                            .foregroundColor(Theme.textPrimary)

                        Spacer()

                        Image(systemName: "arrow.right.from.line")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                }

                sectionDivider

                // Delete account
                Button {
                    viewModel.showDeleteConfirmation = true
                } label: {
                    HStack {
                        Text("Delete Account")
                            .font(.custom("OpenSauceSans-Regular", size: 15))
                            .foregroundColor(Color(red: 0.85, green: 0.25, blue: 0.22))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Shared Components

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("OpenSauceSans-Medium", size: 13))
            .foregroundColor(Theme.textTertiary)
            .padding(.horizontal, 4)
    }

    private var sectionDivider: some View {
        Divider()
            .background(Color(red: 0.94, green: 0.94, blue: 0.93))
            .padding(.leading, 16)
    }
}
