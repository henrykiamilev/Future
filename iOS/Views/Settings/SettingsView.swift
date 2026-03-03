import SwiftUI
import PhotosUI

struct SettingsView: View {

    @StateObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    let profile: UserProfile
    @State private var selectedPhoto: PhotosPickerItem?
    @AppStorage("appAppearance") private var appearanceRaw: String = AppAppearance.light.rawValue

    // Card entrance animation
    @State private var cardsAppeared = false

    // Warm gradient colors (matches ShuffleCardView activity bar)
    private let warmGradient = LinearGradient(
        colors: [
            Color(red: 0.91, green: 0.66, blue: 0.49),
            Color(red: 0.83, green: 0.37, blue: 0.37)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    profileCard
                        .cardEntrance(index: 0, appeared: cardsAppeared)

                    controlsCard
                        .cardEntrance(index: 1, appeared: cardsAppeared)

                    aboutCard
                        .cardEntrance(index: 2, appeared: cardsAppeared)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 80)
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
                                await viewModel.saveNotificationPreferences()
                                if viewModel.error == nil { dismiss() }
                            }
                        } label: {
                            Text("Save")
                                .font(.custom("OpenSauceSans-SemiBold", size: 14))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 7)
                                .background(warmGradient)
                                .clipShape(Capsule())
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
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                    cardsAppeared = true
                }
            }
            .task { await viewModel.loadBlockedUsersCount() }
            .onChange(of: viewModel.didSignOut) { _, newValue in
                if newValue { dismiss() }
            }
        }
    }

    // MARK: - Profile Card (Live Preview + Edit)

    private var profileCard: some View {
        VStack(spacing: 0) {
            // Warm gradient accent bar at top of card
            warmGradient.frame(height: 3)

            VStack(spacing: 0) {
                // ── Live Profile Preview ──
                profilePreview
                    .padding(.bottom, 20)

                // ── Thin gradient separator ──
                gradientDivider

                // ── Edit Fields ──
                VStack(spacing: 0) {
                    editableField("Display name", text: $viewModel.displayName)
                    thinDivider
                    editableBio("Bio", text: $viewModel.bio)
                }
                .padding(.top, 4)

                // ── Connected Accounts ──
                NavigationLink {
                    ConnectedAccountsView(viewModel: viewModel)
                } label: {
                    connectedAccountsRow
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
    }

    // MARK: - Live Profile Preview (how others see you)

    private var profilePreview: some View {
        VStack(spacing: 16) {
            // Row 1: Avatar + Identity
            HStack(spacing: 16) {
                // Avatar
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        CachedImageView(
                            url: SupabaseConfig.storageURL(for: viewModel.profilePhotoURL ?? ""),
                            targetSize: CGSize(width: 168, height: 168)
                        ) {
                            Circle()
                                .fill(Theme.separator)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(Theme.textTertiary)
                                }
                        }
                        .frame(width: 76, height: 76)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

                        if viewModel.isUploadingPhoto {
                            Circle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 76, height: 76)
                                .overlay { ProgressView().tint(.white) }
                        }

                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.background)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            .offset(x: 2, y: 2)
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

                // Name + username
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.displayName.isEmpty ? profile.username : viewModel.displayName)
                        .font(.custom("OpenSauceSans-SemiBold", size: 20))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    Text("@\(profile.username)")
                        .font(.custom("OpenSauceSans-Regular", size: 13))
                        .foregroundColor(Theme.textTertiary)

                    // Bio preview (inline with identity)
                    if !viewModel.bio.isEmpty {
                        Text(viewModel.bio)
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }

                Spacer()
            }

            // Row 2: Stats bar
            HStack(spacing: 0) {
                statItem(value: profile.followerCount, label: "followers")
                Spacer()
                Rectangle().fill(Theme.separator).frame(width: 0.5, height: 28)
                Spacer()
                statItem(value: profile.followingCount, label: "following")
                Spacer()
                Rectangle().fill(Theme.separator).frame(width: 0.5, height: 28)
                Spacer()
                statItem(value: profile.totalLikes, label: "likes")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(Theme.separator.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Row 3: Signature post thumbnails
            HStack(spacing: 6) {
                ForEach(profile.signaturePosts.prefix(3), id: \.id) { post in
                    CachedImageView(
                        url: SupabaseConfig.storageURL(for: post.imageURL),
                        targetSize: CGSize(width: 120, height: 120)
                    ) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.separator.opacity(0.5))
                    }
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                // Empty signature slots
                ForEach(0..<max(0, 3 - profile.signaturePosts.count), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.separator.opacity(0.25))
                        .frame(height: 72)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(Theme.textTertiary.opacity(0.4))
                        }
                }
            }
        }
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.custom("OpenSauceSans-SemiBold", size: 14))
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(.custom("OpenSauceSans-Regular", size: 10))
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - Connected Accounts Row

    private var connectedAccountsRow: some View {
        VStack(spacing: 0) {
            thinDivider

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected accounts")
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.textPrimary)

                    Text(connectedAccountsSummary)
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer()

                HStack(spacing: -6) {
                    accountDot("camera.fill", connected: !viewModel.instagramHandle.isEmpty, color: Color(red: 0.83, green: 0.18, blue: 0.42))
                    accountDot("message.fill", connected: !viewModel.snapchatHandle.isEmpty, color: Color(red: 0.95, green: 0.85, blue: 0.20))
                    accountDot("play.rectangle.fill", connected: !viewModel.tiktokHandle.isEmpty, color: Theme.textPrimary)
                    accountDot("at", connected: !viewModel.xHandle.isEmpty, color: Theme.textPrimary)
                    accountDot("globe", connected: !viewModel.websiteURL.isEmpty, color: Color(red: 0.20, green: 0.50, blue: 0.85))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.leading, 6)
            }
            .padding(.top, 14)
            .padding(.bottom, 2)
        }
    }

    private func accountDot(_ icon: String, connected: Bool, color: Color) -> some View {
        Circle()
            .fill(connected ? color.opacity(0.15) : Theme.separator.opacity(0.5))
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(connected ? color : Theme.textTertiary.opacity(0.5))
            }
            .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 1.5))
    }

    private var connectedAccountsSummary: String {
        let count = [
            viewModel.instagramHandle, viewModel.snapchatHandle,
            viewModel.tiktokHandle, viewModel.xHandle, viewModel.websiteURL
        ].filter { !$0.isEmpty }.count
        return count == 0 ? "Add your socials" : "\(count) linked"
    }

    // MARK: - Controls Card (Privacy + Notifications + Appearance + Wellbeing)

    private var controlsCard: some View {
        VStack(spacing: 0) {
            // Card header
            HStack {
                Text("CONTROLS")
                    .font(Theme.sectionHeaderFont)
                    .tracking(1.5)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)

            // ── Privacy ──
            miniSectionLabel("Privacy")

            settingsToggle(
                "Allow comments",
                subtitle: "Let others comment on your posts",
                isOn: Binding(
                    get: { viewModel.commentsEnabled },
                    set: { _ in Task { await viewModel.toggleComments() } }
                )
            )
            thinDivider
            settingsToggle(
                "Private account",
                subtitle: "Only approved followers see your posts",
                isOn: Binding(
                    get: { viewModel.visibility == .private },
                    set: { _ in Task { await viewModel.toggleVisibility() } }
                )
            )
            thinDivider
            NavigationLink {
                BlockedUsersView(profileService: viewModel.profileService)
            } label: {
                settingsNavRow(
                    "Blocked users",
                    trailingText: viewModel.blockedUsersCount > 0 ? "\(viewModel.blockedUsersCount)" : nil
                )
            }
            .buttonStyle(.plain)

            gradientDivider.padding(.vertical, 4)

            // ── Notifications ──
            miniSectionLabel("Notifications")

            settingsToggle("Likes", isOn: $viewModel.notifyLikes)
            thinDivider
            settingsToggle("Comments", isOn: $viewModel.notifyComments)
            thinDivider
            settingsToggle("New followers", isOn: $viewModel.notifyFollows)
            thinDivider
            settingsToggle("Reactions", isOn: $viewModel.notifyReactions)

            gradientDivider.padding(.vertical, 4)

            // ── Appearance ──
            miniSectionLabel("Appearance")

            HStack {
                Text("App theme")
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appearanceRaw = appearance.rawValue
                            }
                        } label: {
                            Text(appearance.rawValue)
                                .font(.custom("OpenSauceSans-Medium", size: 11))
                                .foregroundColor(
                                    appearanceRaw == appearance.rawValue
                                        ? Theme.background : Theme.textSecondary
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    appearanceRaw == appearance.rawValue
                                        ? Theme.accent : Theme.separator.opacity(0.5)
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            gradientDivider.padding(.vertical, 4)

            // ── Wellbeing ──
            miniSectionLabel("Wellbeing")

            VStack(alignment: .leading, spacing: Theme.spacingS) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session reminder")
                            .font(Theme.headlineFont)
                            .foregroundColor(Theme.textPrimary)
                        Text("Nudge to take a break")
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer()
                }

                HStack(spacing: 5) {
                    ForEach(SessionDuration.allCases) { duration in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.sessionDuration = duration
                            }
                        } label: {
                            Text(duration.rawValue)
                                .font(.custom("OpenSauceSans-Medium", size: 11))
                                .foregroundColor(
                                    viewModel.sessionDuration == duration
                                        ? .white : Theme.textSecondary
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    viewModel.sessionDuration == duration
                                        ? AnyShapeStyle(warmGradient)
                                        : AnyShapeStyle(Theme.separator.opacity(0.5))
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 4)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
    }

    // MARK: - About Card (Support + Account)

    private var aboutCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ABOUT")
                    .font(Theme.sectionHeaderFont)
                    .tracking(1.5)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)

            Button {
                if let url = URL(string: "mailto:support@getcurated.app") {
                    UIApplication.shared.open(url)
                }
            } label: { settingsNavRow("Help & Feedback") }
            .buttonStyle(.plain)

            thinDivider

            Button {
                if let url = URL(string: "https://getcurated.app/terms") {
                    UIApplication.shared.open(url)
                }
            } label: { settingsNavRow("Terms of Service") }
            .buttonStyle(.plain)

            thinDivider

            Button {
                if let url = URL(string: "https://getcurated.app/privacy") {
                    UIApplication.shared.open(url)
                }
            } label: { settingsNavRow("Privacy Policy") }
            .buttonStyle(.plain)

            gradientDivider.padding(.vertical, 4)

            // Account actions
            Button { viewModel.clearCache() } label: {
                actionRow("Clear cache", icon: "trash")
            }
            thinDivider
            Button { viewModel.signOut() } label: {
                actionRow("Sign out", icon: "arrow.right.from.line")
            }
            thinDivider
            Button { viewModel.showDeleteConfirmation = true } label: {
                HStack {
                    Text("Delete account")
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.likeActive)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            // Version
            Text("Curated v\(appVersion)")
                .font(.custom("OpenSauceSans-Regular", size: 11))
                .foregroundColor(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Reusable Components

    private func editableField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.custom("OpenSauceSans-Regular", size: 11))
                .foregroundColor(Theme.textTertiary)
                .tracking(0.3)
            TextField(label, text: text)
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func editableBio(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.custom("OpenSauceSans-Regular", size: 11))
                .foregroundColor(Theme.textTertiary)
                .tracking(0.3)
            TextField("Write something about yourself", text: text, axis: .vertical)
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(3...6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func miniSectionLabel(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.custom("OpenSauceSans-Medium", size: 10))
                .tracking(1.0)
                .foregroundColor(Theme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func settingsToggle(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textTertiary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(CuratedToggleStyle())
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func settingsNavRow(_ title: String, trailingText: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            if let trailingText {
                Text(trailingText)
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.separator)
                    .clipShape(Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func actionRow(_ title: String, icon: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private var gradientDivider: some View {
        LinearGradient(
            colors: [
                Color(red: 0.91, green: 0.66, blue: 0.49).opacity(0.3),
                Color(red: 0.83, green: 0.37, blue: 0.37).opacity(0.3)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 0.5)
        .padding(.horizontal, 16)
    }
}

// MARK: - Card Entrance Animation

private struct CardEntranceModifier: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
            .scaleEffect(appeared ? 1 : 0.97)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8)
                    .delay(Double(index) * 0.06),
                value: appeared
            )
    }
}

extension View {
    func cardEntrance(index: Int, appeared: Bool) -> some View {
        modifier(CardEntranceModifier(index: index, appeared: appeared))
    }
}

// MARK: - Custom Toggle Style

struct CuratedToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Capsule()
                .fill(configuration.isOn ? Theme.accent : Theme.separator)
                .frame(width: 44, height: 26)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Theme.background : Color.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        .padding(2)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
