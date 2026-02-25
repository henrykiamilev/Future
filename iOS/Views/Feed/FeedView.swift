import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// FeedView — Vertical Scrolling Gallery Feed
// ═══════════════════════════════════════════════════════════════════════════
//
// • Cream (#F9F4E6) background — no white anywhere.
// • Tall rounded rectangle cards housing each photo.
// • Tap a card → full-screen expansion (Instagram Reels style).
// • Segmented control (Friends / Discover) at top via toolbar (dark text).
// • Long-press on a card → action sheet (React, Report).
// • Pull-to-refresh.
//
// ═══════════════════════════════════════════════════════════════════════════

struct FeedView: View {

    @StateObject var viewModel: FeedViewModel

    // MARK: - Full-screen expansion

    @State private var expandedPost: FeedPost?

    // MARK: - Reaction

    @State private var showReactionPicker = false
    @State private var reactionPostID: UUID?

    // MARK: - Report

    @State private var reportingPostID: UUID?
    @State private var showReportSheet = false
    @State private var showReportConfirmation = false

    var body: some View {
        feedContent
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                inlineSegmentedControl
            }
        }
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
        // ── Reaction picker overlay ──
        .overlay {
            if showReactionPicker, let postID = reactionPostID {
                reactionOverlay(for: postID)
            }
        }
        // ── Full-screen photo expansion ──
        .fullScreenCover(item: $expandedPost) { post in
            FeedFullScreenView(
                post: post,
                onDismiss: { expandedPost = nil },
                onProfileTapped: {
                    expandedPost = nil
                }
            )
        }
        .task {
            viewModel.startSessionTracking()
            await viewModel.loadInitial()
        }
        // ── Report dialogs ──
        .confirmationDialog("Report Post", isPresented: $showReportSheet, titleVisibility: .visible) {
            Button("Spam") { submitReport(reason: "spam") }
            Button("Harassment or Bullying") { submitReport(reason: "harassment") }
            Button("Inappropriate Content") { submitReport(reason: "inappropriate") }
            Button("Other") { submitReport(reason: "other") }
            Button("Cancel", role: .cancel) { reportingPostID = nil }
        } message: {
            Text("Why are you reporting this post?")
        }
        .alert("Report Submitted", isPresented: $showReportConfirmation) {
            Button("OK", role: .cancel) { reportingPostID = nil }
        } message: {
            Text("Thanks for letting us know. We'll review this post.")
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

    private var postList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Top spacing so first card doesn't sit right against nav bar
                Spacer().frame(height: 12)

                ForEach(viewModel.posts) { post in
                    FeedPostCard(
                        post: post,
                        onReactTapped: {
                            reactionPostID = post.id
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showReactionPicker = true
                            }
                        },
                        onTap: {
                            expandedPost = post
                        }
                    )
                    // Long-press → action sheet
                    .contextMenu {
                        Button {
                            reactionPostID = post.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showReactionPicker = true
                                }
                            }
                        } label: {
                            Label("React", systemImage: "face.smiling")
                        }

                        Button(role: .destructive) {
                            reportingPostID = post.id
                            showReportSheet = true
                        } label: {
                            Label("Report", systemImage: "exclamationmark.triangle")
                        }
                    }
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
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Reaction Overlay

    private func reactionOverlay(for postID: UUID) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.25)) {
                        showReactionPicker = false
                        reactionPostID = nil
                    }
                }

            HStack(spacing: 22) {
                ForEach(ReactionPicker.emojis, id: \.self) { emoji in
                    Button {
                        Task { await viewModel.reactToPost(postID, emoji: emoji) }
                        withAnimation(.spring(response: 0.25)) {
                            showReactionPicker = false
                            reactionPostID = nil
                        }
                    } label: {
                        Text(emoji)
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
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

    // MARK: - Helpers

    private func submitReport(reason: String) {
        if let id = reportingPostID {
            Task { await viewModel.reportPost(id: id, reason: reason) }
        }
        showReportConfirmation = true
    }
}
