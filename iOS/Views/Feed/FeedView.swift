import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// FeedView — Vertical Scrolling Gallery Feed
// ═══════════════════════════════════════════════════════════════════════════
//
// • Cream (#F9F4E6) background — no white anywhere.
// • Tall rounded rectangle cards housing each photo.
// • Tap a card → full-screen expansion (Instagram Reels style).
// • Segmented control (Friends / Discover) at top via toolbar (dark text).
// • Double-tap → like with haptic + heart animation.
// • Long-press → emoji reaction picker anchored to bottom of post image.
// • Pull-to-refresh.
//
// ═══════════════════════════════════════════════════════════════════════════

struct FeedView: View {

    @StateObject var viewModel: FeedViewModel
    @EnvironmentObject private var appState: AppState

    // MARK: - Full-screen expansion

    @State private var expandedPost: FeedPost?
    @State private var profileUserID: UUID?
    @State private var showProfile = false

    // MARK: - Reaction

    @State private var showReactionPicker = false
    @State private var reactionPostID: UUID?

    var body: some View {
        feedContent
        .background(Theme.background)
        .navigationBarHidden(true)
        // ── Session reminder ──
        .overlay {
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
        }
        // ── Full-screen photo expansion ──
        .fullScreenCover(item: $expandedPost, onDismiss: {
            // After full-screen cover finishes dismissing, navigate to profile if pending
            if profileUserID != nil {
                showProfile = true
            }
        }) { post in
            FeedFullScreenView(
                post: post,
                onDismiss: { expandedPost = nil },
                onProfileTapped: {
                    // Store the userID, then dismiss instantly using transaction
                    profileUserID = post.userID
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        expandedPost = nil
                    }
                }
            )
        }
        // Push profile view after full-screen dismisses
        .navigationDestination(isPresented: $showProfile) {
            if let userID = profileUserID {
                ProfileView(viewModel: appState.makeProfileViewModel(userID: userID))
                    .onDisappear { profileUserID = nil }
            }
        }
        .task {
            viewModel.startSessionTracking()
            await viewModel.loadInitial()
        }
    }

    // MARK: - Inline Segmented Control (dark text on cream)

    private var inlineSegmentedControl: some View {
        HStack(spacing: 28) {
            ForEach(FeedSegment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedSegment = segment
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(segment.rawValue)
                            .font(.custom("OpenSauceSans-SemiBold", size: 16))
                            .foregroundColor(
                                viewModel.selectedSegment == segment
                                    ? Theme.textPrimary
                                    : Theme.textTertiary
                            )

                        // Thin underline for selected tab
                        Rectangle()
                            .fill(
                                viewModel.selectedSegment == segment
                                    ? Theme.textPrimary
                                    : Color.clear
                            )
                            .frame(width: 30, height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.posts.isEmpty {
            Spacer()
            ProgressView().tint(Theme.textTertiary)
            Spacer()
        } else if let error = viewModel.error, viewModel.posts.isEmpty {
            Spacer()
            errorView(error)
            Spacer()
        } else if viewModel.selectedSegment == .friends && viewModel.isFriendsCaughtUp && viewModel.posts.isEmpty {
            CaughtUpView(
                discoveryRemaining: viewModel.discoveryRemaining,
                onExplore: { viewModel.selectedSegment = .discover }
            )
        } else if viewModel.selectedSegment == .discover && viewModel.isDiscoveryExhausted && viewModel.posts.isEmpty {
            DiscoveryEndView()
        } else if viewModel.posts.isEmpty {
            Spacer()
            emptyView
            Spacer()
        } else {
            postList
        }
    }

    // MARK: - Post List (vertical scroll)

    // MARK: - Floating Header (Friends / Discover + Bell)

    private var floatingHeader: some View {
        HStack {
            inlineSegmentedControl

            Spacer()

            NotificationBellButton(viewModel: appState.makeNotificationViewModel())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var postList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Spacer().frame(height: 4)

                ForEach(viewModel.posts) { post in
                    FeedPostCard(
                        post: post,
                        showReactionPicker: showReactionPicker && reactionPostID == post.id,
                        onTap: {
                            expandedPost = post
                        },
                        onDoubleTap: {
                            // Haptic feedback
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()

                            // Always call toggleLike — the function handles
                            // both like/unlike and updates the count correctly.
                            Task { await viewModel.toggleLike(post: post) }
                        },
                        onLongPress: {
                            // Haptic feedback for long press
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()

                            reactionPostID = post.id
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showReactionPicker = true
                            }
                        },
                        onReaction: { emoji in
                            // Haptic on reaction select
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()

                            Task { await viewModel.reactToPost(post.id, emoji: emoji) }
                            withAnimation(.spring(response: 0.25)) {
                                showReactionPicker = false
                                reactionPostID = nil
                            }
                        }
                    )
                    .task {
                        await viewModel.loadMoreIfNeeded(currentPost: post)
                        viewModel.recordPostSeen(post)
                        await viewModel.loadReactions(for: [post.id])
                    }
                }

                // Caught-up inline
                if viewModel.selectedSegment == .friends && viewModel.isFriendsCaughtUp {
                    CaughtUpView(
                        discoveryRemaining: viewModel.discoveryRemaining,
                        onExplore: { viewModel.selectedSegment = .discover }
                    )
                }

                // Discovery end inline
                if viewModel.selectedSegment == .discover && viewModel.isDiscoveryExhausted {
                    DiscoveryEndView()
                }

                // Show more (discovery)
                if viewModel.selectedSegment == .discover && !viewModel.isDiscoveryExhausted {
                    Button {
                        Task { await viewModel.loadMoreDiscovery() }
                    } label: {
                        Text("Show more")
                            .font(Theme.headlineFont)
                            .foregroundColor(Theme.accent)
                            .padding(.vertical, Theme.spacingM)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .tint(Theme.textTertiary)
                        .padding(.vertical, Theme.spacingL)
                }

                // Bottom padding for custom tab bar
                Spacer().frame(height: 80)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            floatingHeader
                .background(Theme.background)
        }
        .refreshable {
            await viewModel.refresh()
        }
        // Dismiss reaction picker on scroll tap
        .overlay {
            if showReactionPicker {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25)) {
                            showReactionPicker = false
                            reactionPostID = nil
                        }
                    }
                    .allowsHitTesting(true)
            }
        }
    }

    // MARK: - Empty / Error States

    private var emptyView: some View {
        VStack(spacing: Theme.spacingM) {
            Text("Nothing here yet")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)

            Text(viewModel.selectedSegment == .friends
                 ? "Follow people to see their posts."
                 : "Check back later for new discoveries.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.spacingM) {
            Text("Something went wrong")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)

            Text(message)
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await viewModel.refresh() }
            }
            .font(Theme.headlineFont)
            .foregroundColor(Theme.accent)
        }
        .padding(.horizontal, Theme.spacingXL)
    }
}
