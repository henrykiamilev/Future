import SwiftUI
import Combine

struct ProfileView: View {

    @StateObject var viewModel: ProfileViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showFollowList = false
    @State private var followListPath = NavigationPath()
    @State private var followListInitialSegment: FollowListViewModel.Segment = .followers
    @State private var showArchiveForSignature = false
    @State private var showCuratedPage = false
    @State private var expandedPost: PostSummary?
    @State private var appeared = false

    // Enhancement states
    @State private var cycleIndex = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var tappedStat: String?
    @State private var pulsingDot = false

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    private let hPad: CGFloat = 24

    // Warm gradient colors
    private let warmStart = Color(red: 0.91, green: 0.66, blue: 0.49)
    private let warmEnd = Color(red: 0.83, green: 0.37, blue: 0.37)

    private var cycleTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()
    }

    // Collected unique tags from all signature posts
    private var signatureTags: [Tag] {
        var seen = Set<String>()
        return viewModel.signaturePosts.flatMap(\.tags).filter { seen.insert($0.label).inserted }
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
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        profileHeader
                            .sectionEntrance(index: 0, appeared: appeared)

                        statsRow
                            .sectionEntrance(index: 1, appeared: appeared)

                        signatureSection
                            .sectionEntrance(index: 2, appeared: appeared)

                        liveSection
                            .sectionEntrance(index: 3, appeared: appeared)

                        if viewModel.isOwnProfile {
                            archiveRow
                                .sectionEntrance(index: 4, appeared: appeared)
                        }
                    }
                    .padding(.bottom, 100)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("profileScroll")).minY)
                        }
                    )
                }
                .coordinateSpace(name: "profileScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    scrollOffset = value
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
        .sheet(isPresented: $showSettings, onDismiss: {
            Task { await viewModel.load() }
        }) {
            if let profile = viewModel.profile,
               let settingsVM = appState.makeSettingsViewModel() {
                SettingsView(
                    viewModel: settingsVM,
                    profile: profile
                )
            }
        }
        .sheet(isPresented: $showCuratedPage) {
            CuratedPageView(
                viewModel: appState.makeCuratedPageViewModel(
                    userID: viewModel.userID,
                    isOwnProfile: viewModel.isOwnProfile
                )
            )
        }
        .fullScreenCover(item: $expandedPost) { post in
            ProfileFullScreenView(
                imageURL: post.imageURL,
                username: viewModel.username,
                onDismiss: { expandedPost = nil }
            )
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.05)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulsingDot = true
            }
        }
        .onReceive(cycleTimer) { _ in
            guard viewModel.signaturePosts.count >= 3 else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                cycleIndex += 1
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Warm Gradient Divider
    // ═══════════════════════════════════════════════════════════════════

    private var warmDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [warmStart.opacity(0.3), warmEnd.opacity(0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.horizontal, hPad)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Profile Header
    // ═══════════════════════════════════════════════════════════════════

    private var profileHeader: some View {
        VStack(spacing: 0) {
            // Avatar with gradient ring
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [warmStart, warmEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                CachedImageView(
                    url: SupabaseConfig.storageURL(for: viewModel.profilePhotoURL ?? ""),
                    targetSize: CGSize(width: 200, height: 200)
                ) {
                    Circle()
                        .fill(Theme.background)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Theme.textTertiary)
                        }
                }
                .frame(width: 92, height: 92)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.background, lineWidth: 3))
            }
            .padding(.top, 24)

            // Display name — large editorial
            if let displayName = viewModel.displayName, !displayName.isEmpty {
                Text(displayName)
                    .font(.custom("OpenSauceSans-SemiBold", size: 26))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.top, 14)
            }

            // Username
            Text("@\(viewModel.username)")
                .font(.custom("OpenSauceSans-Regular", size: 14))
                .foregroundColor(Theme.textTertiary)
                .padding(.top, 2)

            // Bio
            if let bio = viewModel.profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.custom("OpenSauceSans-Regular", size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, hPad + 16)
                    .padding(.top, 8)
            }

            // "curated" link — understated
            Button {
                showCuratedPage = true
            } label: {
                HStack(spacing: 4) {
                    Text("curated")
                        .font(.custom("OpenSauceSans-Medium", size: 12))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(Theme.textTertiary)
            }
            .padding(.top, 10)

            // Streak badge
            if !viewModel.isOwnProfile && viewModel.streakCount > 0 {
                streakBadge
                    .padding(.top, 10)
            }

            // Social links
            SocialLinksRow(
                instagramHandle: viewModel.instagramHandle,
                snapchatHandle: viewModel.snapchatHandle
            )
            .padding(.top, 12)

            // Follow button
            if !viewModel.isOwnProfile {
                followButton
                    .padding(.horizontal, hPad)
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    // Follow button with warm gradient outline when following
    private var followButton: some View {
        Button {
            Task { await viewModel.toggleFollow() }
        } label: {
            Text(followButtonLabel)
                .font(.custom("OpenSauceSans-SemiBold", size: 14))
                .foregroundColor(viewModel.isFollowing ? Theme.textSecondary : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    viewModel.isFollowing
                        ? AnyShapeStyle(Color.clear)
                        : AnyShapeStyle(Theme.accent)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if viewModel.isFollowing {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [warmStart, warmEnd],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                }
        }
    }

    private var followButtonLabel: String {
        if viewModel.isFollowing { return "Following" }
        if viewModel.followIsPending { return "Requested" }
        return "Follow"
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Stats Row
    // ═══════════════════════════════════════════════════════════════════

    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(value: viewModel.totalLikes, label: "likes", key: "likes")

            statColumn(value: viewModel.followerCount, label: "followers", key: "followers") {
                followListInitialSegment = .followers
                showFollowList = true
            }

            statColumn(value: viewModel.followingCount, label: "following", key: "following") {
                followListInitialSegment = .following
                showFollowList = true
            }
        }
        .padding(.horizontal, hPad)
        .padding(.bottom, 32)
        .sheet(isPresented: $showFollowList, onDismiss: { followListPath = NavigationPath() }) {
            NavigationStack(path: $followListPath) {
                FollowListView(
                    viewModel: appState.makeFollowListViewModel(userID: viewModel.userID),
                    initialSegment: followListInitialSegment,
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

    // Stats with tap micro-interaction (scale + haptic)
    private func statColumn(value: Int, label: String, key: String, action: (() -> Void)? = nil) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            tappedStat = key
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                tappedStat = nil
            }
            action?()
        } label: {
            VStack(spacing: 2) {
                Text(formatStat(value))
                    .font(.custom("OpenSauceSans-SemiBold", size: 20))
                    .foregroundColor(Theme.textPrimary)
                Text(label)
                    .font(.custom("OpenSauceSans-Regular", size: 12))
                    .foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(tappedStat == key ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: tappedStat)
        }
        .buttonStyle(.plain)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Signature Section
    // ═══════════════════════════════════════════════════════════════════

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                warmDivider

                HStack {
                    Text("SIGNATURE")
                        .font(.custom("OpenSauceSans-SemiBold", size: 11))
                        .tracking(1.5)
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, hPad)
                .padding(.top, 14)
            }

            if viewModel.signaturePosts.isEmpty && viewModel.isOwnProfile {
                emptySignaturePlaceholderOwn
            } else if viewModel.signaturePosts.isEmpty {
                emptySignaturePlaceholder
            } else {
                signatureMosaic
            }
        }
        .padding(.bottom, 28)
        .sheet(isPresented: $showArchiveForSignature, onDismiss: {
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

    private var signatureMosaic: some View {
        let totalWidth = screenWidth - (hPad * 2)
        let spacing: CGFloat = 6
        let posts = viewModel.signaturePosts
        let leftW = totalWidth * 0.58
        let rightW = totalWidth * 0.42 - spacing
        let fullH = totalWidth * 0.72
        let halfH = (fullH - spacing) / 2

        return Group {
            if posts.count == 1 {
                HStack(spacing: spacing) {
                    signatureTile(posts[0], width: leftW, height: fullH, tileIndex: 0)

                    VStack(spacing: spacing) {
                        if viewModel.isOwnProfile {
                            Button { showArchiveForSignature = true } label: {
                                addSlot(width: rightW, height: halfH)
                            }
                            .buttonStyle(.plain)
                            Button { showArchiveForSignature = true } label: {
                                addSlot(width: rightW, height: halfH)
                            }
                            .buttonStyle(.plain)
                        } else {
                            emptySlotView(width: rightW, height: halfH)
                            emptySlotView(width: rightW, height: halfH)
                        }
                    }
                }
                .padding(.horizontal, hPad)
            } else if posts.count == 2 {
                HStack(spacing: spacing) {
                    signatureTile(posts[0], width: leftW, height: fullH, tileIndex: 0)

                    VStack(spacing: spacing) {
                        signatureTile(posts[1], width: rightW, height: halfH, tileIndex: 1)

                        if viewModel.isOwnProfile {
                            Button { showArchiveForSignature = true } label: {
                                addSlot(width: rightW, height: halfH)
                            }
                            .buttonStyle(.plain)
                        } else {
                            emptySlotView(width: rightW, height: halfH)
                        }
                    }
                }
                .padding(.horizontal, hPad)
            } else {
                // Image cycling — right slots swap every 3.5s
                let topRight = cycleIndex % 2 == 0 ? posts[1] : posts[2]
                let bottomRight = cycleIndex % 2 == 0 ? posts[2] : posts[1]

                HStack(spacing: spacing) {
                    // Left panel with tag overlay
                    signatureTileWithTags(posts[0], width: leftW, height: fullH)

                    VStack(spacing: spacing) {
                        signatureTile(topRight, width: rightW, height: halfH, tileIndex: 1)
                            .id("sigB-\(topRight.id)")
                            .transition(.opacity)

                        signatureTile(bottomRight, width: rightW, height: halfH, tileIndex: 2)
                            .id("sigC-\(bottomRight.id)")
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, hPad)
            }
        }
    }

    // Tag strip overlay (matches ShuffleCardView pattern)
    private var tagStripOverlay: some View {
        HStack(spacing: 6) {
            ForEach(signatureTags.prefix(3)) { tag in
                Text(tag.label)
                    .font(.custom("OpenSauceSans-Medium", size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial.opacity(0.7))
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.5), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // Left panel tile with tag capsules + parallax (3-post mosaic only)
    private func signatureTileWithTags(_ post: PostSummary, width: CGFloat, height: CGFloat) -> some View {
        Button {
            expandedPost = post
        } label: {
            CachedImageView(
                url: SupabaseConfig.storageURL(for: post.imageURL),
                targetSize: CGSize(width: width * 2, height: height * 2)
            ) {
                Rectangle().fill(Theme.separator.opacity(0.5))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .offset(x: scrollOffset * 0.02, y: scrollOffset * 0.01)
            .overlay(alignment: .bottom) {
                if !signatureTags.isEmpty {
                    tagStripOverlay
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if post.likeCount > 0 {
                    likeOverlay(count: post.likeCount)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85).delay(0),
                value: appeared
            )
        }
        .buttonStyle(.plain)
        .if(viewModel.isOwnProfile) { view in
            view.contextMenu {
                Button(role: .destructive) {
                    Task { await viewModel.removeFromSignature(postID: post.id) }
                } label: {
                    Label("Remove from Signature", systemImage: "star.slash")
                }
            }
        }
    }

    // Parallax + staggered entrance per tile
    private func signatureTile(_ post: PostSummary, width: CGFloat, height: CGFloat, tileIndex: Int) -> some View {
        let parallaxFactors: [CGFloat] = [0.02, 0.04, 0.06]
        let factor = parallaxFactors[min(tileIndex, parallaxFactors.count - 1)]

        return Button {
            expandedPost = post
        } label: {
            CachedImageView(
                url: SupabaseConfig.storageURL(for: post.imageURL),
                targetSize: CGSize(width: width * 2, height: height * 2)
            ) {
                Rectangle().fill(Theme.separator.opacity(0.5))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .offset(x: scrollOffset * factor, y: scrollOffset * (factor * 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if post.likeCount > 0 {
                    likeOverlay(count: post.likeCount)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(tileIndex) * 0.08),
                value: appeared
            )
        }
        .buttonStyle(.plain)
        .if(viewModel.isOwnProfile) { view in
            view.contextMenu {
                Button(role: .destructive) {
                    Task { await viewModel.removeFromSignature(postID: post.id) }
                } label: {
                    Label("Remove from Signature", systemImage: "star.slash")
                }
            }
        }
    }

    private func addSlot(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.separator.opacity(0.2))
            .frame(width: width, height: height)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(Theme.textTertiary.opacity(0.6))
            }
    }

    private func emptySlotView(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.separator.opacity(0.15))
            .frame(width: width, height: height)
    }

    private var emptySignaturePlaceholderOwn: some View {
        Button {
            showArchiveForSignature = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "star")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(Theme.textTertiary)
                Text("Pin your best posts")
                    .font(.custom("OpenSauceSans-Medium", size: 13))
                    .foregroundColor(Theme.textSecondary)
                Text("Open Archive to select up to 3")
                    .font(.custom("OpenSauceSans-Regular", size: 12))
                    .foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .buttonStyle(.plain)
    }

    private var emptySignaturePlaceholder: some View {
        Text("No signature posts yet")
            .font(.custom("OpenSauceSans-Regular", size: 13))
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Live Section
    // ═══════════════════════════════════════════════════════════════════

    private var liveSection: some View {
        let tileWidth = (screenWidth - (hPad * 2) - 12) / 3

        return VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                warmDivider

                HStack(spacing: 6) {
                    Text("LIVE")
                        .font(.custom("OpenSauceSans-SemiBold", size: 11))
                        .tracking(1.5)
                        .foregroundColor(Theme.textTertiary)

                    // Pulsing green dot
                    if !viewModel.livePosts.isEmpty {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                            .opacity(pulsingDot ? 1.0 : 0.3)
                    }

                    Spacer()
                }
                .padding(.horizontal, hPad)
                .padding(.top, 14)
            }

            if viewModel.livePosts.isEmpty {
                Text("No live posts")
                    .font(.custom("OpenSauceSans-Regular", size: 13))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                HStack(spacing: 6) {
                    ForEach(viewModel.livePosts) { post in
                        liveTile(post, size: tileWidth)
                    }

                    ForEach(0 ..< max(0, 3 - viewModel.livePosts.count), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.separator.opacity(0.15))
                            .frame(width: tileWidth, height: tileWidth * 1.25)
                    }
                }
                .padding(.horizontal, hPad)
            }
        }
        .padding(.bottom, 28)
    }

    private func liveTile(_ post: PostSummary, size: CGFloat) -> some View {
        Button {
            expandedPost = post
        } label: {
            CachedImageView(
                url: SupabaseConfig.storageURL(for: post.imageURL),
                targetSize: CGSize(width: size * 2, height: size * 2.5)
            ) {
                Rectangle().fill(Theme.separator.opacity(0.5))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size * 1.25)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if post.likeCount > 0 {
                    likeOverlay(count: post.likeCount)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Archive Row
    // ═══════════════════════════════════════════════════════════════════

    private var archiveRow: some View {
        VStack(spacing: 0) {
            warmDivider

            Button {
                viewModel.toggleArchive()
            } label: {
                HStack {
                    Image(systemName: "archivebox")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Theme.textTertiary)
                    Text("Archive")
                        .font(.custom("OpenSauceSans-Medium", size: 14))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, 18)
            }
            .sheet(isPresented: $viewModel.showArchive) {
                ArchiveView(viewModel: viewModel)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Shared Components
    // ═══════════════════════════════════════════════════════════════════

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
        .cornerRadius(6)
        .padding(6)
    }

    private var streakBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            Text("\(viewModel.streakCount)")
                .font(.custom("OpenSauceSans-SemiBold", size: 13))
                .foregroundColor(Theme.textPrimary)
            Text("day streak")
                .font(.custom("OpenSauceSans-Regular", size: 12))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.10))
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

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Section Entrance Animation

private struct SectionEntranceModifier: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(index) * 0.05),
                value: appeared
            )
    }
}

private extension View {
    func sectionEntrance(index: Int, appeared: Bool) -> some View {
        modifier(SectionEntranceModifier(index: index, appeared: appeared))
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ProfileFullScreenView
// ═══════════════════════════════════════════════════════════════════════════

struct ProfileFullScreenView: View {

    let imageURL: String
    let username: String
    let onDismiss: () -> Void

    private let screenWidth = UIScreen.main.bounds.width
    private let screenHeight = UIScreen.main.bounds.height

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CachedImageView(
                url: SupabaseConfig.storageURL(for: imageURL),
                targetSize: CGSize(width: screenWidth * 2, height: screenHeight * 2)
            ) {
                Rectangle()
                    .fill(Color(white: 0.08))
                    .overlay {
                        ProgressView().tint(.white.opacity(0.3))
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: screenWidth, height: screenHeight)
            .clipped()
            .ignoresSafeArea()

            VStack {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.6), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                Spacer()
                HStack {
                    Text(username)
                        .font(.custom("OpenSauceSans-SemiBold", size: 16))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 150 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}
