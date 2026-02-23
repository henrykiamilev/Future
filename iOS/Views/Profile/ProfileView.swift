import SwiftUI

struct ProfileView: View {

    @StateObject var viewModel: ProfileViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showFollowList = false
    @State private var followListPath = NavigationPath()
    @State private var showArchiveForSignature = false

    private var theme: ProfileTheme {
        guard let slug = viewModel.profile?.profileTheme else { return .default }
        return ProfileTheme(rawValue: slug) ?? .default
    }

    private func signatureTileSize(for width: CGFloat) -> CGFloat {
        (width - 48 - 16) / 3
    }
    private func liveTileSize(for width: CGFloat) -> CGFloat {
        (width - 48 - 16) / 3 * 0.78
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.profile == nil {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(Theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.profile == nil {
                VStack(spacing: Theme.spacingM) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36, weight: .thin))
                        .foregroundColor(Theme.textTertiary)
                    Text("Couldn't load profile")
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.textPrimary)
                    Text(error)
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacingXL)
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Text("Retry")
                            .font(Theme.headlineFont)
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.spacingL)
                            .padding(.vertical, Theme.spacingS)
                            .background(Theme.accent)
                            .cornerRadius(Theme.radiusM)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        profileHeader
                        statsRow
                        signatureSection(width: geometry.size.width)
                        liveSection(width: geometry.size.width)
                        archiveButton
                    }
                    .padding(.bottom, Theme.spacingXXL)
                }
                }
            }
        }
        .background(theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isOwnProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(theme.textPrimary)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            if let profile = viewModel.profile,
               let settingsVM = appState.makeSettingsViewModel() {
                SettingsView(
                    viewModel: settingsVM,
                    profile: profile
                )
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Profile Header
    // PRD: [ Profile Photo – centered ] [ Username ]

    private var profileHeader: some View {
        VStack(spacing: Theme.spacingS) {
            // Centered avatar — Instagram-style circular profile photo
            CachedImageView(
                url: SupabaseConfig.storageURL(for: viewModel.profilePhotoURL ?? ""),
                targetSize: CGSize(width: 160, height: 160)
            ) {
                Circle()
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

            // Username
            Text(viewModel.username)
                .font(Theme.titleFont)
                .foregroundColor(theme.textPrimary)

            // Streak badge (non-own profiles with active streak)
            if !viewModel.isOwnProfile && viewModel.streakCount > 0 {
                streakBadge
            }

            // Social links (Instagram / Snapchat deep link buttons)
            SocialLinksRow(
                instagramHandle: viewModel.instagramHandle,
                snapchatHandle: viewModel.snapchatHandle
            )

            // Follow button (non-own profiles)
            if !viewModel.isOwnProfile {
                followButton
                    .padding(.top, Theme.spacingXS)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.spacingL)
        .padding(.bottom, Theme.spacingL)
    }

    private var followButton: some View {
        Button {
            Task { await viewModel.toggleFollow() }
        } label: {
            Text(followButtonLabel)
                .font(Theme.headlineFont)
                .foregroundColor(viewModel.isFollowing ? theme.textSecondary : .white)
                .padding(.horizontal, Theme.spacingL)
                .padding(.vertical, Theme.spacingS)
                .background(viewModel.isFollowing ? theme.background : theme.accent)
                .cornerRadius(Theme.radiusM)
                .overlay {
                    if viewModel.isFollowing {
                        RoundedRectangle(cornerRadius: Theme.radiusM)
                            .strokeBorder(Theme.separator, lineWidth: 1)
                    }
                }
        }
    }

    private var followButtonLabel: String {
        if viewModel.isFollowing { return "Following" }
        if viewModel.followIsPending { return "Requested" }
        return "Follow"
    }

    // MARK: - Stats Row
    // PRD: Total Likes (lifetime) | Followers | Following
    // PRD: Stats visually secondary to Signature.

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: viewModel.totalLikes, label: "Likes", tappable: false)

            Button { showFollowList = true } label: {
                statItem(value: viewModel.followerCount, label: "Followers", tappable: true)
            }
            .buttonStyle(.plain)

            Button { showFollowList = true } label: {
                statItem(value: viewModel.followingCount, label: "Following", tappable: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.bottom, Theme.spacingXL)
        .sheet(isPresented: $showFollowList, onDismiss: { followListPath = NavigationPath() }) {
            NavigationStack(path: $followListPath) {
                FollowListView(
                    viewModel: appState.makeFollowListViewModel(userID: viewModel.userID),
                    onUserTapped: { userID in
                        followListPath.append(userID)
                    }
                )
                .navigationDestination(for: UUID.self) { userID in
                    ProfileView(viewModel: appState.makeProfileViewModel(userID: userID))
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showFollowList = false }
                            .font(Theme.headlineFont)
                            .foregroundColor(Theme.accent)
                    }
                }
            }
        }
    }

    private func statItem(value: Int, label: String, tappable: Bool) -> some View {
        VStack(spacing: 2) {
            Text(formatStat(value))
                .font(Theme.statNumberFont)
                .foregroundColor(theme.textPrimary)

            Text(label)
                .font(Theme.statLabelFont)
                .foregroundColor(tappable ? theme.accent : theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Signature Section
    // PRD: — Signature — [ 3 Large Tiles – manually selected ]

    private func signatureSection(width: CGFloat) -> some View {
        let tileSize = signatureTileSize(for: width)
        return VStack(alignment: .leading, spacing: Theme.spacingM) {
            sectionHeader("Signature")

            if viewModel.signaturePosts.isEmpty && viewModel.isOwnProfile {
                emptySignaturePlaceholderOwn
            } else if viewModel.signaturePosts.isEmpty {
                emptySignaturePlaceholder
            } else {
                HStack(spacing: Theme.spacingS) {
                    ForEach(viewModel.signaturePosts) { post in
                        signatureTile(post, size: tileSize)
                    }

                    // Empty slots — tappable on own profile to open archive
                    ForEach(0 ..< max(0, 3 - viewModel.signaturePosts.count), id: \.self) { _ in
                        if viewModel.isOwnProfile {
                            Button {
                                showArchiveForSignature = true
                            } label: {
                                addSignatureSlot(size: tileSize)
                            }
                            .buttonStyle(.plain)
                        } else {
                            emptyTile(size: tileSize)
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingL)
            }
        }
        .padding(.bottom, Theme.spacingXL)
        .sheet(isPresented: $showArchiveForSignature, onDismiss: {
            // Refresh profile to pick up any signature changes made in archive
            Task { await viewModel.load() }
        }) {
            ArchiveView(viewModel: viewModel)
                .onAppear {
                    if viewModel.archivePosts.isEmpty {
                        Task { await viewModel.loadArchive() }
                    }
                }
        }
    }

    private func signatureTile(_ post: PostSummary, size: CGFloat) -> some View {
        CachedImageView(
            url: SupabaseConfig.storageURL(for: post.imageURL),
            targetSize: CGSize(width: size * 2, height: size * 2.5)
        ) {
            Rectangle().fill(Theme.separator)
        }
        .frame(width: size, height: size * 1.25)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(alignment: .bottomLeading) {
            if post.likeCount > 0 {
                likeOverlay(count: post.likeCount)
            }
        }
        .if(viewModel.isOwnProfile) { view in
            view.contextMenu {
                Button(role: .destructive) {
                    Task {
                        await viewModel.removeFromSignature(postID: post.id)
                    }
                } label: {
                    Label("Remove from Signature", systemImage: "star.slash")
                }
            }
        }
    }

    /// Tappable empty slot with "+" icon — only shown on own profile
    private func addSignatureSlot(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Theme.radiusM)
            .fill(Theme.separator.opacity(0.4))
            .frame(width: size, height: size * 1.25)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                    Text("Add")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textTertiary)
                }
            }
    }

    private var emptySignaturePlaceholderOwn: some View {
        Button {
            showArchiveForSignature = true
        } label: {
            VStack(spacing: Theme.spacingS) {
                Image(systemName: "star")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(Theme.textTertiary)
                Text("Pin your best posts")
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textSecondary)
                Text("Open Archive to select up to 3")
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacingL)
        }
        .buttonStyle(.plain)
    }

    private var emptySignaturePlaceholder: some View {
        Text("No signature posts yet")
            .font(Theme.captionFont)
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacingL)
    }

    // MARK: - Live Section
    // PRD: — Live — [ 3 Medium Tiles – last 3 active posts ]

    private func liveSection(width: CGFloat) -> some View {
        let tileSize = liveTileSize(for: width)
        return VStack(alignment: .leading, spacing: Theme.spacingM) {
            sectionHeader("Live")

            if viewModel.livePosts.isEmpty {
                emptyLivePlaceholder
            } else {
                HStack(spacing: Theme.spacingS) {
                    ForEach(viewModel.livePosts) { post in
                        liveTile(post, size: tileSize)
                    }

                    ForEach(0 ..< max(0, 3 - viewModel.livePosts.count), id: \.self) { _ in
                        emptyTile(size: tileSize)
                    }
                }
                .padding(.horizontal, Theme.spacingL)
            }
        }
        .padding(.bottom, Theme.spacingXL)
    }

    private func liveTile(_ post: PostSummary, size: CGFloat) -> some View {
        CachedImageView(
            url: SupabaseConfig.storageURL(for: post.imageURL),
            targetSize: CGSize(width: size * 2, height: size * 2.5)
        ) {
            Rectangle().fill(Theme.separator)
        }
        .frame(width: size, height: size * 1.25)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(alignment: .bottomLeading) {
            if post.likeCount > 0 {
                likeOverlay(count: post.likeCount)
            }
        }
    }

    private var emptyLivePlaceholder: some View {
        Text("No live posts")
            .font(Theme.captionFont)
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacingL)
    }

    // MARK: - Archive Button

    @ViewBuilder
    private var archiveButton: some View {
        if viewModel.isOwnProfile {
            Button {
                viewModel.toggleArchive()
            } label: {
                HStack(spacing: Theme.spacingS) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 14, weight: .regular))
                    Text("Archive")
                        .font(Theme.headlineFont)
                }
                .foregroundColor(theme.textSecondary)
                .padding(.vertical, Theme.spacingS)
            }
            .padding(.top, Theme.spacingM)
            .sheet(isPresented: $viewModel.showArchive) {
                ArchiveView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.sectionHeaderFont)
            .foregroundColor(theme.textSecondary)
            .tracking(1.5)
            .padding(.horizontal, Theme.spacingL)
    }

    private func emptyTile(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Theme.radiusM)
            .fill(Theme.separator.opacity(0.4))
            .frame(width: size, height: size * 1.25)
    }

    private func likeOverlay(count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 8))
            Text(formatStat(count))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.radiusS)
        .padding(6)
    }

    private var streakBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            Text("\(viewModel.streakCount)")
                .font(Theme.headlineFont)
                .foregroundColor(theme.textPrimary)
            Text(viewModel.streakCount == 1 ? "day streak" : "day streak")
                .font(Theme.captionFont)
                .foregroundColor(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.12))
        )
    }

    private func formatStat(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
