import SwiftUI

struct ProfileView: View {

    @StateObject var viewModel: ProfileViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false

    private let signatureTileSize: CGFloat = (UIScreen.main.bounds.width - 48 - 16) / 3
    private let liveTileSize: CGFloat = (UIScreen.main.bounds.width - 48 - 16) / 3 * 0.78

    var body: some View {
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
            // Centered avatar
            AsyncImage(url: URL(string: viewModel.profilePhotoURL ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())

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
            statItem(value: viewModel.totalLikes, label: "Likes")
            statItem(value: viewModel.followerCount, label: "Followers")
            statItem(value: viewModel.followingCount, label: "Following")
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.bottom, Theme.spacingXL)
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(formatStat(value))
                .font(Theme.statNumberFont)
                .foregroundColor(Theme.textPrimary)

            Text(label)
                .font(Theme.statLabelFont)
                .foregroundColor(Theme.textTertiary)
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
                    ForEach(0 ..< (3 - viewModel.signaturePosts.count), id: \.self) { _ in
                        emptyTile(size: signatureTileSize)
                    }
                }
                .padding(.horizontal, Theme.spacingL)
            }
        }
        .padding(.bottom, Theme.spacingXL)
    }

    private func signatureTile(_ post: PostSummary) -> some View {
        AsyncImage(url: URL(string: post.imageURL)) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
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
        HStack(spacing: Theme.spacingS) {
            ForEach(0..<3, id: \.self) { _ in
                emptyTile(size: signatureTileSize)
            }
        }
        .padding(.horizontal, Theme.spacingL)
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

                    ForEach(0 ..< (3 - viewModel.livePosts.count), id: \.self) { _ in
                        emptyTile(size: liveTileSize)
                    }
                }
                .padding(.horizontal, Theme.spacingL)
            }
        }
        .padding(.bottom, Theme.spacingXL)
    }

    private func liveTile(_ post: PostSummary) -> some View {
        AsyncImage(url: URL(string: post.imageURL)) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
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
        HStack(spacing: Theme.spacingS) {
            ForEach(0..<3, id: \.self) { _ in
                emptyTile(size: liveTileSize)
            }
        }
        .padding(.horizontal, Theme.spacingL)
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
