import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var displayName: String = ""
    @Published var bio: String = ""
    @Published var instagramHandle: String = ""
    @Published var snapchatHandle: String = ""
    @Published var visibility: User.AccountVisibility = .public
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?
    @Published var showDeleteConfirmation = false
    @Published private(set) var didSignOut = false

    // MARK: - Dependencies

    private let profileService: ProfileServiceProtocol
    private let authService: AuthServiceProtocol

    init(profileService: ProfileServiceProtocol, authService: AuthServiceProtocol) {
        self.profileService = profileService
        self.authService = authService
    }

    // MARK: - Load from Profile

    func loadFrom(profile: UserProfile) {
        displayName = profile.user.displayName ?? ""
        bio = profile.user.bio ?? ""
        instagramHandle = profile.user.instagramHandle ?? ""
        snapchatHandle = profile.user.snapchatHandle ?? ""
        visibility = profile.user.visibility
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

    // MARK: - Sign Out

    func signOut() {
        authService.signOut()
        didSignOut = true
    }
}
