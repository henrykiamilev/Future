import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// FeedView — Full-Screen Gallery Feed
// ═══════════════════════════════════════════════════════════════════════════
//
// Behavior:
//   • One post fills the entire screen (photo + white panel).
//   • Swipe up/down pages between posts (TabView with .page).
//   • Single tap toggles immersive mode (hides chrome).
//   • Long-press opens blurred action sheet (react, share, report).
//   • Segmented control at top for Friends / Discover.
//   • Tab bar hidden in immersive mode.
//
// ═══════════════════════════════════════════════════════════════════════════

struct FeedView: View {

    @StateObject var viewModel: FeedViewModel

    // MARK: - Chrome / Immersive State

    @State private var chromeVisible = true

    // MARK: - Long-Press Action Sheet

    @State private var showActionSheet = false
    @State private var actionSheetPostID: UUID?

    // MARK: - Reaction Picker

    @State private var showReactionPicker = false
    @State private var reactionPostID: UUID?

    // MARK: - Report Flow

    @State private var reportingPostID: UUID?
    @State private var showReportSheet = false
    @State private var showReportConfirmation = false

    // MARK: - Paging

    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack {
            // Background — always dark behind the photo
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.posts.isEmpty {
                loadingView
            } else if let error = viewModel.error, viewModel.posts.isEmpty {
                errorView(error)
            } else if viewModel.posts.isEmpty {
                emptyView
            } else {
                pagedFeed
            }

            // ── Segmented control at top ──
            if chromeVisible && !viewModel.posts.isEmpty {
                VStack {
                    segmentedControl
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── Session Reminder Overlay ──
            if viewModel.showSessionReminder {
                SessionReminderView(
                    onKeepGoing: { viewModel.dismissSessionReminder() },
                    onClose: {
                        viewModel.dismissSessionReminder()
                        viewModel.stopSessionTracking()
                    }
                )
                .transition(.opacity)
            }

            // ── Reaction Picker Overlay ──
            if showReactionPicker, let postID = reactionPostID {
                reactionOverlay(for: postID)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: chromeVisible)
        .navigationBarHidden(true)
        .statusBarHidden(!chromeVisible)
        .task {
            viewModel.startSessionTracking()
            await viewModel.loadInitial()
        }

        // ── Report confirmation dialog ──
        .confirmationDialog("Report Post", isPresented: $showReportSheet, titleVisibility: .visible) {
            Button("Spam") {
                submitReport(reason: "spam")
            }
            Button("Harassment or Bullying") {
                submitReport(reason: "harassment")
            }
            Button("Inappropriate Content") {
                submitReport(reason: "inappropriate")
            }
            Button("Other") {
                submitReport(reason: "other")
            }
            Button("Cancel", role: .cancel) {
                reportingPostID = nil
            }
        } message: {
            Text("Why are you reporting this post?")
        }
        .alert("Report Submitted", isPresented: $showReportConfirmation) {
            Button("OK", role: .cancel) {
                reportingPostID = nil
            }
        } message: {
            Text("Thanks for letting us know. We'll review this post.")
        }

        // ── Long-press action sheet ──
        .confirmationDialog("", isPresented: $showActionSheet, titleVisibility: .hidden) {
            Button("React") {
                reactionPostID = actionSheetPostID
                showReactionPicker = true
            }
            Button("Report") {
                reportingPostID = actionSheetPostID
                showReportSheet = true
            }
            Button("Cancel", role: .cancel) {
                actionSheetPostID = nil
            }
        }
    }

    // MARK: - Paged Feed (one post per screen)

    private var pagedFeed: some View {
        GeometryReader { geometry in
            let cardHeight = geometry.size.height

            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.posts.enumerated()), id: \.element.id) { index, post in
                    FeedPostCard(
                        post: post,
                        onReactTapped: {
                            reactionPostID = post.id
                            showReactionPicker = true
                        },
                        onProfileTapped: {
                            // Navigation handled via NavigationStack in parent
                        },
                        cardHeight: cardHeight,
                        chromeVisible: chromeVisible
                    )
                    .tag(index)
                    // Single tap — toggle chrome
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            chromeVisible.toggle()
                        }
                    }
                    // Long-press — action sheet
                    .onLongPressGesture(minimumDuration: 0.4) {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        actionSheetPostID = post.id
                        showActionSheet = true
                    }
                    .onAppear {
                        viewModel.recordPostSeen(post)
                        Task {
                            await viewModel.loadMoreIfNeeded(currentPost: post)
                            await viewModel.loadReactions(for: [post.id])
                        }
                    }
                }

                // Caught-up / end states as final "pages"
                if viewModel.selectedSegment == .friends && viewModel.isFriendsCaughtUp {
                    CaughtUpView(
                        discoveryRemaining: viewModel.discoveryRemaining,
                        onExplore: { viewModel.selectedSegment = .discover }
                    )
                    .tag(viewModel.posts.count)
                }

                if viewModel.selectedSegment == .discover && viewModel.isDiscoveryExhausted {
                    DiscoveryEndView()
                        .tag(viewModel.posts.count)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(FeedSegment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedSegment = segment
                        currentIndex = 0
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(segment.rawValue)
                            .font(.custom("OpenSauceSans-Medium", size: 14))
                            .foregroundColor(
                                viewModel.selectedSegment == segment
                                    ? .white
                                    : .white.opacity(0.5)
                            )

                        // Progress indicator
                        progressLabel(for: segment)

                        Rectangle()
                            .fill(
                                viewModel.selectedSegment == segment
                                    ? Color.white
                                    : Color.clear
                            )
                            .frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.5), location: 0),
                    .init(color: .black.opacity(0.0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder
    private func progressLabel(for segment: FeedSegment) -> some View {
        switch segment {
        case .friends:
            if viewModel.isFriendsCaughtUp {
                Text("caught up")
                    .font(.custom("OpenSauceSans-Regular", size: 10))
                    .foregroundColor(.white.opacity(0.4))
            } else if viewModel.friendsPostsSeen > 0 || viewModel.friendsRemaining > 0 {
                let total = viewModel.friendsPostsSeen + viewModel.friendsRemaining
                Text("\(viewModel.friendsPostsSeen) of \(total)")
                    .font(.custom("OpenSauceSans-Regular", size: 10))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Text(" ")
                    .font(.custom("OpenSauceSans-Regular", size: 10))
            }
        case .discover:
            if viewModel.isDiscoveryExhausted {
                Text("done")
                    .font(.custom("OpenSauceSans-Regular", size: 10))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Text("\(viewModel.discoveryItemsSeen)/15")
                    .font(.custom("OpenSauceSans-Regular", size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Reaction Overlay

    private func reactionOverlay(for postID: UUID) -> some View {
        ZStack {
            // Tap backdrop to dismiss
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.25)) {
                        showReactionPicker = false
                        reactionPostID = nil
                    }
                }

            // Emoji row — centered
            HStack(spacing: 24) {
                ForEach(ReactionPicker.emojis, id: \.self) { emoji in
                    Button {
                        Task { await viewModel.reactToPost(postID, emoji: emoji) }
                        withAnimation(.spring(response: 0.25)) {
                            showReactionPicker = false
                            reactionPostID = nil
                        }
                    } label: {
                        Text(emoji)
                            .font(.system(size: 36))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showReactionPicker)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(.white.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Text("Something went wrong")
                .font(.custom("OpenSauceSans-Medium", size: 16))
                .foregroundColor(.white)

            Text(message)
                .font(.custom("OpenSauceSans-Regular", size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await viewModel.refresh() }
            }
            .font(.custom("OpenSauceSans-Medium", size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            )
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var emptyView: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Text("Nothing here yet")
                .font(.custom("OpenSauceSans-Medium", size: 16))
                .foregroundColor(.white)

            Text(viewModel.selectedSegment == .friends
                 ? "Follow people to see their posts."
                 : "Check back later for new discoveries.")
                .font(.custom("OpenSauceSans-Regular", size: 14))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
    }

    // MARK: - Helpers

    private func submitReport(reason: String) {
        if let id = reportingPostID {
            Task { await viewModel.reportPost(id: id, reason: reason) }
        }
        showReportConfirmation = true
    }
}
