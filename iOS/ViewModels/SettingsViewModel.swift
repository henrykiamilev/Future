import Foundation
import UIKit

@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var displayName: String = ""
    @Published var bio: String = ""
    @Published var instagramHandle: String = ""
    @Published var snapchatHandle: String = ""
    @Published var visibility: User.AccountVisibility = .public
    @Published var commentsEnabled: Bool = false
    @Published private(set) var isSaving = false
    @Published var error: String?
    @Published var showDeleteConfirmation = false
    @Published private(set) var didSignOut = false
    @Published private(set) var isUploadingPhoto = false
    @Published var profilePhotoURL: String?
    @Published var profileTheme: ProfileTheme = .default

    // MARK: - Dependencies

    private let profileService: ProfileServiceProtocol
    private let authService: AuthServiceProtocol
    private let imageUploadService: ImageUploadServiceProtocol
    private let currentUserID: UUID

    init(
        profileService: ProfileServiceProtocol,
        authService: AuthServiceProtocol,
        imageUploadService: ImageUploadServiceProtocol,
        currentUserID: UUID
    ) {
        self.profileService = profileService
        self.authService = authService
        self.imageUploadService = imageUploadService
        self.currentUserID = currentUserID
    }

    // MARK: - Load from Profile

    func loadFrom(profile: UserProfile) {
        displayName = profile.displayName ?? ""
        bio = profile.bio ?? ""
        instagramHandle = profile.instagramHandle ?? ""
        snapchatHandle = profile.snapchatHandle ?? ""
        visibility = profile.visibility
        commentsEnabled = profile.commentsEnabled
        profilePhotoURL = profile.profilePhotoURL
        profileTheme = ProfileTheme(rawValue: profile.profileTheme) ?? .default
    }

    // MARK: - Save Profile

    func saveProfile() async {
        isSaving = true
        error = nil

        // Client-side validation (mirrors server CHECK constraints)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIG = instagramHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSnap = snapchatHandle.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedName.isEmpty && trimmedName.count > 100 {
            error = "Display name must be 100 characters or fewer."
            isSaving = false
            return
        }
        if !trimmedBio.isEmpty && trimmedBio.count > 500 {
            error = "Bio must be 500 characters or fewer."
            isSaving = false
            return
        }
        if !trimmedIG.isEmpty && trimmedIG.count > 50 {
            error = "Instagram handle must be 50 characters or fewer."
            isSaving = false
            return
        }
        if !trimmedSnap.isEmpty && trimmedSnap.count > 50 {
            error = "Snapchat handle must be 50 characters or fewer."
            isSaving = false
            return
        }

        do {
            // Send empty string (not nil) to clear fields — nil omits the key from PATCH
            let update = ProfileUpdate(
                displayName: trimmedName,
                bio: trimmedBio,
                instagramHandle: trimmedIG,
                snapchatHandle: trimmedSnap
            )
            try await profileService.updateProfile(update, userID: currentUserID)
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Visibility Toggle

    func toggleVisibility() async {
        let newVisibility: User.AccountVisibility = visibility == .public ? .private : .public
        isSaving = true

        do {
            try await profileService.updateVisibility(newVisibility, userID: currentUserID)
            visibility = newVisibility
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Comments Toggle

    func toggleComments() async {
        let newValue = !commentsEnabled
        isSaving = true

        do {
            try await profileService.updateCommentsEnabled(newValue, userID: currentUserID)
            commentsEnabled = newValue
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Profile Photo

    func uploadProfilePhoto(_ image: UIImage) async {
        isUploadingPhoto = true

        do {
            let uploaded = try await imageUploadService.upload(image: image, onProgress: { _ in })
            try await profileService.updateProfilePhoto(url: uploaded.url, userID: currentUserID)
            profilePhotoURL = uploaded.url
        } catch {
            self.error = error.localizedDescription
        }

        isUploadingPhoto = false
    }

    // MARK: - Profile Theme

    func updateTheme(_ theme: ProfileTheme) async {
        let previous = profileTheme
        profileTheme = theme

        do {
            try await profileService.updateProfileTheme(theme.rawValue, userID: currentUserID)
        } catch {
            profileTheme = previous
            self.error = error.localizedDescription
        }
    }

    // MARK: - Delete Account

    func deleteAccount() async {
        isSaving = true
        error = nil

        do {
            try await profileService.deleteAccount()
            authService.signOut()
            didSignOut = true
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Sign Out

    func signOut() {
        authService.signOut()
        didSignOut = true
    }
}
