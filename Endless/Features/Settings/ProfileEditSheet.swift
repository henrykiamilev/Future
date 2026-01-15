import SwiftUI
import PhotosUI

/// Sheet for editing profile name and image.
struct ProfileEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var userService = UserService.shared

    @State private var displayName: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: Image?
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Profile image
                    profileImageSection

                    // Display name
                    displayNameSection

                    // Email (read-only)
                    emailSection
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background(for: colorScheme))
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            loadCurrentProfile()
        }
        .onChange(of: selectedPhoto) { _, newItem in
            loadSelectedPhoto(newItem)
        }
    }

    // MARK: - Profile Image Section

    private var profileImageSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Image display
            ZStack(alignment: .bottomTrailing) {
                if let profileImage = profileImage {
                    profileImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else if let imageUrl = userService.currentProfile?.profileImageUrl,
                          let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        profilePlaceholder
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                } else {
                    profilePlaceholder
                        .frame(width: 100, height: 100)
                }

                // Edit badge
                Circle()
                    .fill(Theme.FallbackColors.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    )
            }

            // Photo picker
            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text("Change Photo")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.FallbackColors.accent)
            }
        }
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(Theme.FallbackColors.accentSubtle)
            .overlay(
                Text(initials)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.FallbackColors.accent)
            )
    }

    private var initials: String {
        let name = displayName.isEmpty ? "U" : displayName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Display Name Section

    private var displayNameSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("NAME")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            TextField("Display name", text: $displayName)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
        }
    }

    // MARK: - Email Section

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("EMAIL")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            Text(userService.currentProfile?.email ?? "")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)

            Text("Email cannot be changed")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
        }
    }

    // MARK: - Actions

    private func loadCurrentProfile() {
        if let profile = userService.currentProfile {
            displayName = profile.displayName ?? ""
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item = item else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                profileImage = Image(uiImage: uiImage)
            }
        }
    }

    private func saveProfile() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true

        Task {
            do {
                // Note: Profile image upload would require a separate endpoint
                // For now, we just update the display name
                _ = try await userService.updateProfile(displayName: trimmedName)
                dismiss()
            } catch {
                errorMessage = "Failed to save profile"
                isSaving = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Profile Edit") {
    ProfileEditSheet()
}
