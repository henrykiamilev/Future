import Foundation
import UIKit

@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Profile Fields

    @Published var displayName: String = ""
    @Published var bio: String = ""
    @Published var instagramHandle: String = ""
    @Published var snapchatHandle: String = ""
    @Published var tiktokHandle: String = ""
    @Published var xHandle: String = ""
    @Published var websiteURL: String = ""
    @Published var visibility: User.AccountVisibility = .public
    @Published var commentsEnabled: Bool = false
    @Published var profilePhotoURL: String?

    // MARK: - Notification Preferences

    @Published var notifyLikes: Bool = true
    @Published var notifyComments: Bool = true
    @Published var notifyFollows: Bool = true
    @Published var notifyReactions: Bool = true

    // MARK: - Appearance

    @Published var profileTheme: ProfileTheme = .default

    // MARK: - Wellbeing

    @Published var sessionDuration: SessionDuration = .ten {
        didSet {
            UserDefaults.standard.set(sessionDuration.rawValue, forKey: "sessionReminderDuration")
        }
    }

    // MARK: - Blocked Users

    @Published var blockedUsersCount: Int = 0

    // MARK: - UI State

    @Published private(set) var isSaving = false
    @Published var error: String?
    @Published var showDeleteConfirmation = false
    @Published private(set) var didSignOut = false
    @Published private(set) var isUploadingPhoto = false

    // MARK: - Dependencies

    let profileService: ProfileServiceProtocol
    private let authService: AuthServiceProtocol
    private let imageUploadService: ImageUploadServiceProtocol
    let currentUserID: UUID

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

        // Load session duration from UserDefaults
        if let raw = UserDefaults.standard.string(forKey: "sessionReminderDuration"),
           let duration = SessionDuration(rawValue: raw) {
            self.sessionDuration = duration
        }
    }

    // MARK: - Load from Profile

    func loadFrom(profile: UserProfile) {
        displayName = profile.displayName ?? ""
        bio = profile.bio ?? ""
        instagramHandle = profile.instagramHandle ?? ""
        snapchatHandle = profile.snapchatHandle ?? ""
        tiktokHandle = profile.tiktokHandle ?? ""
        xHandle = profile.xHandle ?? ""
        websiteURL = profile.websiteURL ?? ""
        visibility = profile.visibility
        commentsEnabled = profile.commentsEnabled
        profilePhotoURL = profile.profilePhotoURL
        notifyLikes = profile.notifyLikes
        notifyComments = profile.notifyComments
        notifyFollows = profile.notifyFollows
        notifyReactions = profile.notifyReactions
        if let theme = profile.profileTheme, let pt = ProfileTheme(rawValue: theme) {
            profileTheme = pt
        }
    }

    // MARK: - Save Profile

    func saveProfile() async {
        isSaving = true
        error = nil

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIG = instagramHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSnap = snapchatHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTiktok = tiktokHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedX = xHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWeb = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)

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
        for (handle, name) in [(trimmedIG, "Instagram"), (trimmedSnap, "Snapchat"), (trimmedTiktok, "TikTok"), (trimmedX, "X")] {
            if !handle.isEmpty && handle.count > 50 {
                error = "\(name) handle must be 50 characters or fewer."
                isSaving = false
                return
            }
        }
        if !trimmedWeb.isEmpty && trimmedWeb.count > 200 {
            error = "Website URL must be 200 characters or fewer."
            isSaving = false
            return
        }

        do {
            let update = ProfileUpdate(
                displayName: trimmedName,
                bio: trimmedBio,
                instagramHandle: trimmedIG,
                snapchatHandle: trimmedSnap,
                tiktokHandle: trimmedTiktok,
                xHandle: trimmedX,
                websiteURL: trimmedWeb
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

    // MARK: - Notification Preferences

    func saveNotificationPreferences() async {
        do {
            let prefs = NotificationPreferencesUpdate(
                notify_likes: notifyLikes,
                notify_comments: notifyComments,
                notify_follows: notifyFollows,
                notify_reactions: notifyReactions
            )
            try await profileService.updateNotificationPreferences(prefs, userID: currentUserID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Profile Theme

    func updateProfileTheme(_ theme: ProfileTheme) async {
        let old = profileTheme
        profileTheme = theme

        do {
            try await profileService.updateProfileTheme(theme.rawValue, userID: currentUserID)
        } catch {
            profileTheme = old
            self.error = error.localizedDescription
        }
    }

    // MARK: - Blocked Users

    func loadBlockedUsersCount() async {
        do {
            let users = try await profileService.getBlockedUsers()
            blockedUsersCount = users.count
        } catch {
            // Silent fail — count stays 0
        }
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

    // MARK: - Cache

    func clearCache() {
        ImageCache.shared.clearDiskCache()
        URLCache.shared.removeAllCachedResponses()
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
