import SwiftUI

struct ProfileView: View {

    @StateObject var viewModel: ProfileViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showFollowList = false

    private let signatureTileSize: CGFloat = (UIScreen.main.bounds.width - 48 - 16) / 3
    private let liveTileSize: CGFloat = (UIScreen.main.bounds.width - 48 - 16) / 3 * 0.78

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
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        profileHeader
                        statsRow
                        signatureSection
                        liveSection
                        archiveButton
                    }
                    .padding(.bottom, Theme.spacingXXL)
                }
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isOwnProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            if let profile = viewModel.profile {
                SettingsView(
                    viewModel: appState.makeSettingsViewModel(),
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
                .foregroundColor(Theme.textPrimary)

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
                .foregroundColor(viewModel.isFollowing ? Theme.textSecondary : .white)
                .padding(.horizontal, Theme.spacingL)
                .padding(.vertical, Theme.spacingS)
                .background(viewModel.isFollowing ? Theme.background : Theme.accent)
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
        .sheet(isPresented: $showFollowList) {
            NavigationStack {
                FollowListView(
                    viewModel: appState.makeFollowListViewModel(userID: viewModel.userID),
                    onUserTapped: { _ in }
                )
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
                .foregroundColor(Theme.textPrimary)

            Text(label)
                .font(Theme.statLabelFont)
                .foregroundColor(tappable ? Theme.accent : Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Signature Section
    // PRD: — Signature — [ 3 Large Tiles – manually selected ]

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            sectionHeader("Signature")

            if viewModel.signaturePosts.isEmpty {
                emptySignaturePlaceholder
            } else {
                HStack(spacing: Theme.spacingS) {
                    ForEach(viewModel.signaturePosts) { post in
                        signatureTile(post)
                    }

                    // Empty slots
                    ForEach(0 ..< max(0, 3 - viewModel.signaturePosts.count), id: \.self) { _ in
                        emptyTile(size: signatureTileSize)
                    }
                }
                .padding(.horizontal, Theme.spacingL)
            }
        }
        .padding(.bottom, Theme.spacingXL)
    }

    private func signatureTile(_ post: PostSummary) -> some View {
        CachedImageView(
            url: SupabaseConfig.storageURL(for: post.imageURL),
            targetSize: CGSize(width: signatureTileSize * 2, height: signatureTileSize * 2.5)
        ) {
            Rectangle().fill(Theme.separator)
        }
        .frame(width: signatureTileSize, height: signatureTileSize * 1.25)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(alignment: .bottomLeading) {
            if post.likeCount > 0 {
                likeOverlay(count: post.likeCount)
            }
        }
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

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            sectionHeader("Live")

            if viewModel.livePosts.isEmpty {
                emptyLivePlaceholder
            } else {
                HStack(spacing: Theme.spacingS) {
                    ForEach(viewModel.livePosts) { post in
                        liveTile(post)
                    }

                    ForEach(0 ..< max(0, 3 - viewModel.livePosts.count), id: \.self) { _ in
                        emptyTile(size: liveTileSize)
                    }
                }
                .padding(.horizontal, Theme.spacingL)
            }
        }
        .padding(.bottom, Theme.spacingXL)
    }

    private func liveTile(_ post: PostSummary) -> some View {
        CachedImageView(
            url: SupabaseConfig.storageURL(for: post.imageURL),
            targetSize: CGSize(width: liveTileSize * 2, height: liveTileSize * 2.5)
        ) {
            Rectangle().fill(Theme.separator)
        }
        .frame(width: liveTileSize, height: liveTileSize * 1.25)
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
                .foregroundColor(Theme.textSecondary)
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
            .foregroundColor(Theme.textTertiary)
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

    private func formatStat(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
