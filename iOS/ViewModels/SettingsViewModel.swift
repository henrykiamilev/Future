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

    // MARK: - Dependencies

    private let profileService: ProfileServiceProtocol
    private let authService: AuthServiceProtocol
    private let imageUploadService: ImageUploadServiceProtocol

    init(
        profileService: ProfileServiceProtocol,
        authService: AuthServiceProtocol,
        imageUploadService: ImageUploadServiceProtocol
    ) {
        self.profileService = profileService
        self.authService = authService
        self.imageUploadService = imageUploadService
    }

    // MARK: - Load from Profile

    func loadFrom(profile: UserProfile) {
        displayName = profile.user.displayName ?? ""
        bio = profile.user.bio ?? ""
        instagramHandle = profile.user.instagramHandle ?? ""
        snapchatHandle = profile.user.snapchatHandle ?? ""
        visibility = profile.user.visibility
        commentsEnabled = profile.user.commentsEnabled
        profilePhotoURL = profile.user.profilePhotoURL
    }

    // MARK: - Save Profile

    func saveProfile() async {
        isSaving = true
        error = nil

        do {
            let update = ProfileUpdate(
                displayName: displayName.isEmpty ? nil : displayName,
                bio: bio.isEmpty ? nil : bio,
                instagramHandle: instagramHandle.isEmpty ? nil : instagramHandle,
                snapchatHandle: snapchatHandle.isEmpty ? nil : snapchatHandle
            )
            try await profileService.updateProfile(update)
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
            try await profileService.updateVisibility(newVisibility)
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
            try await profileService.updateCommentsEnabled(newValue)
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
            try await profileService.updateProfilePhoto(url: uploaded.url)
            profilePhotoURL = uploaded.url
        } catch {
            self.error = error.localizedDescription
        }

        isUploadingPhoto = false
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
