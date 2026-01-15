import SwiftUI

/// Main settings screen with profile and preferences.
/// Clean, Apple-like grouped list design.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState

    @StateObject private var userService = UserService.shared
    @StateObject private var journalService = JournalService.shared

    @State private var showProfileEdit: Bool = false
    @State private var showSubscriptionInfo: Bool = false
    @State private var showResetJournalConfirm: Bool = false
    @State private var showSignOutConfirm: Bool = false
    @State private var notificationsEnabled: Bool = true
    @State private var darkModeEnabled: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List {
                // Profile section
                profileSection

                // Subscription section
                subscriptionSection

                // Appearance section
                appearanceSection

                // Notifications section
                notificationsSection

                // Journal section
                if journalService.hasSelectedMode {
                    journalSection
                }

                // Support section
                supportSection

                // Account section
                accountSection
            }
            .listStyle(.insetGrouped)
            .background(Theme.Colors.background(for: colorScheme))
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showProfileEdit) {
                ProfileEditSheet()
            }
            .sheet(isPresented: $showSubscriptionInfo) {
                SubscriptionInfoView()
            }
            .alert("Reset Journal Mode", isPresented: $showResetJournalConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetJournalMode()
                }
            } message: {
                Text("This will allow you to choose a new journaling style. Your existing entries will be preserved.")
            }
            .alert("Sign Out", isPresented: $showSignOutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            loadPreferences()
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            Button {
                showProfileEdit = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    // Profile image
                    profileImage

                    // Name and email
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                        if let email = userService.currentProfile?.email {
                            Text(email)
                                .font(Theme.Typography.caption1)
                                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .listRowBackground(Theme.Colors.backgroundSecondary(for: colorScheme))
        }
    }

    private var profileImage: some View {
        Group {
            if let imageUrl = userService.currentProfile?.profileImageUrl,
               let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    profilePlaceholder
                }
            } else {
                profilePlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(Theme.FallbackColors.accentSubtle)
            .overlay(
                Text(initials)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.FallbackColors.accent)
            )
    }

    private var displayName: String {
        userService.currentProfile?.displayName ?? "User"
    }

    private var initials: String {
        let name = displayName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        Section {
            Button {
                showSubscriptionInfo = true
            } label: {
                HStack {
                    Label("Subscription", systemImage: "creditcard")
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                    Spacer()

                    // Tier badge
                    Text(userService.isPro ? "Pro" : "Free")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(userService.isPro ? .white : Theme.Colors.textSecondary(for: colorScheme))
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(userService.isPro
                                    ? Theme.FallbackColors.accent
                                    : Theme.Colors.backgroundSecondary(for: colorScheme))
                        )

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                }
            }
            .listRowBackground(Theme.Colors.backgroundSecondary(for: colorScheme))
        } header: {
            Text("Plan")
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            Toggle(isOn: $darkModeEnabled) {
                Label("Dark Mode", systemImage: "moon")
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
            }
            .tint(Theme.FallbackColors.accent)
            .onChange(of: darkModeEnabled) { _, newValue in
                updateDarkMode(newValue)
            }
            .listRowBackground(Theme.Colors.backgroundSecondary(for: colorScheme))
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                Label("Push Notifications", systemImage: "bell")
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
            }
            .tint(Theme.FallbackColors.accent)
            .onChange(of: notificationsEnabled) { _, newValue in
                updateNotifications(newValue)
            }
            .listRowBackground(Theme.Colors.backgroundSecondary(for: colorScheme))
        } header: {
            Text("Notifications")
        }
    }

    // MARK: - Journal Section

    private var journalSection: some View {
        Section {
            Button {
                showResetJournalConfirm = true
            } label: {
                HStack {
                    Label("Journal Style", systemImage: "book.closed")
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                    Spacer()

                    Text(journalModeLabel)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                }
            }
            .listRowBackground(Theme.Colors.backgroundSecondary(for: colorScheme))
        } header: {
            Text("Journal")
        } footer: {
            Text("You can change your journaling style. Your existing entries will be kept.")
        }
    }

    private var journalModeLabel: String {
        switch journalService.journalMode {
        case .freeText:
            return "Free Writing"
        case .guidedPrompts:
            return "Guided Prompts"
        case .none:
            return "Not Set"
        }
    }

    // MARK: - Support Section

    private var supportSection: some View {
        Section {
            Link(destination: URL(string: "https://endless.app/privacy")!) {
                HStack {
                    Label("Privacy Policy", systemImage: "hand.raised")
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                }
            }
            .listRowBackground(Theme.Colors.backgroundSecondary(for: colorScheme))

            Link(destination: URL(string: "https://endless.app/terms")!) {
                HStack {
                    Label("Terms of Service", systemImage: "doc.text")
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                }
            }
            .listRowBackground(Theme.Colors.backgroundSecondary(for: colorScheme))

            Link(destination: URL(string: "mailto:feedback@endless.app")!) {
                HStack {
                    Label("Send Feedback", systemImage: "envelope")
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                }
            }
            .listRowBackground(Theme.Colors.backgroundSecondary(for: colorScheme))
        } header: {
            Text("Support")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            Button {
                showSignOutConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Sign Out")
                        .font(Theme.Typography.body)
                        .foregroundColor(Color(hex: "E55050"))
                    Spacer()
                }
            }
            .listRowBackground(Theme.Colors.backgroundSecondary(for: colorScheme))
        }
    }

    // MARK: - Actions

    private func loadPreferences() {
        if let profile = userService.currentProfile {
            notificationsEnabled = profile.notificationsEnabled ?? true
            darkModeEnabled = profile.darkModeEnabled ?? false
        }
    }

    private func updateDarkMode(_ enabled: Bool) {
        Task {
            do {
                _ = try await userService.updateProfile(darkModeEnabled: enabled)
                appState.prefersDarkMode = enabled
            } catch {
                errorMessage = "Failed to update preference"
            }
        }
    }

    private func updateNotifications(_ enabled: Bool) {
        Task {
            do {
                _ = try await userService.updateProfile(notificationsEnabled: enabled)
            } catch {
                errorMessage = "Failed to update preference"
            }
        }
    }

    private func resetJournalMode() {
        Task {
            do {
                _ = try await userService.resetJournalMode()
                await journalService.refreshMode()
            } catch {
                errorMessage = "Failed to reset journal mode"
            }
        }
    }

    private func signOut() {
        appState.signOut()
        dismiss()
    }
}

// MARK: - Preview

#Preview("Settings - Light") {
    SettingsView()
        .environmentObject(AppState())
        .preferredColorScheme(.light)
}

#Preview("Settings - Dark") {
    SettingsView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
