import SwiftUI

struct FeedView: View {

    @StateObject var viewModel: FeedViewModel
    @State private var reportingPostID: UUID?
    @State private var showReportSheet = false
    @State private var showReportConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            segmentedControl
            feedContent
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("CURATED")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(2.0)
                    .foregroundColor(Theme.textPrimary)
            }
        }
        .overlay {
            if viewModel.showSessionReminder {
                SessionReminderView(
                    onKeepGoing: { viewModel.dismissSessionReminder() },
                    onClose: {
                        viewModel.dismissSessionReminder()
                        viewModel.stopSessionTracking()
                        // User chose to close — navigate away handled by parent
                    }
                )
                .transition(.opacity)
            }
        }
        .task {
            viewModel.startSessionTracking()
            await viewModel.loadInitial()
        }
        .confirmationDialog("Report Post", isPresented: $showReportSheet, titleVisibility: .visible) {
            Button("Spam") {
                if let id = reportingPostID {
                    Task { await viewModel.reportPost(id: id, reason: "spam") }
                }
                showReportConfirmation = true
            }
            Button("Harassment or Bullying") {
                if let id = reportingPostID {
                    Task { await viewModel.reportPost(id: id, reason: "harassment") }
                }
                showReportConfirmation = true
            }
            Button("Inappropriate Content") {
                if let id = reportingPostID {
                    Task { await viewModel.reportPost(id: id, reason: "inappropriate") }
                }
                showReportConfirmation = true
            }
            Button("Other") {
                if let id = reportingPostID {
                    Task { await viewModel.reportPost(id: id, reason: "other") }
                }
                showReportConfirmation = true
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
    }

    // MARK: - Segmented Control with Progress

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(FeedSegment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedSegment = segment
                    }
                } label: {
                    VStack(spacing: Theme.spacingXS) {
                        Text(segment.rawValue)
                            .font(Theme.headlineFont)
                            .foregroundColor(
                                viewModel.selectedSegment == segment
                                    ? Theme.textPrimary
                                    : Theme.textTertiary
                            )

                        // v2: Progress indicator
                        progressLabel(for: segment)

                        Rectangle()
                            .fill(
                                viewModel.selectedSegment == segment
                                    ? Theme.accent
                                    : Color.clear
                            )
                            .frame(height: 1.5)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.top, Theme.spacingS)
        .background(Theme.background)
    }

    @ViewBuilder
    private func progressLabel(for segment: FeedSegment) -> some View {
        switch segment {
        case .friends:
            if viewModel.isFriendsCaughtUp {
                Text("caught up")
                    .font(Theme.labelFont)
                    .foregroundColor(Theme.textTertiary)
            } else if viewModel.friendsPostsSeen > 0 || viewModel.friendsRemaining > 0 {
                let total = viewModel.friendsPostsSeen + viewModel.friendsRemaining
                Text("\(viewModel.friendsPostsSeen) of \(total)")
                    .font(Theme.labelFont)
                    .foregroundColor(Theme.textTertiary)
            } else {
                Text(" ")
                    .font(Theme.labelFont)
            }
        case .discover:
            if viewModel.isDiscoveryExhausted {
                Text("done")
                    .font(Theme.labelFont)
                    .foregroundColor(Theme.textTertiary)
            } else {
                Text("\(viewModel.discoveryItemsSeen)/15")
                    .font(Theme.labelFont)
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.posts.isEmpty {
            Spacer()
            ProgressView()
                .tint(Theme.textTertiary)
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

    private var postList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spacingXL) {
                ForEach(viewModel.posts) { post in
                    FeedPostCard(
                        post: post,
                        onLikeTapped: { Task { await viewModel.toggleLike(post: post) } },
                        onReportTapped: {
                            reportingPostID = post.id
                            showReportSheet = true
                        },
                        authorDestination: post.userID
                    )
                    .task {
                        await viewModel.loadMoreIfNeeded(currentPost: post)
                        viewModel.recordPostSeen(post)
                    }
                }

                // v2: Inline caught-up state after last post
                if viewModel.selectedSegment == .friends && viewModel.isFriendsCaughtUp {
                    CaughtUpView(
                        discoveryRemaining: viewModel.discoveryRemaining,
                        onExplore: { viewModel.selectedSegment = .discover }
                    )
                    .frame(height: 400)
                }

                // v2: Inline discovery end state after last post
                if viewModel.selectedSegment == .discover && viewModel.isDiscoveryExhausted {
                    DiscoveryEndView()
                        .frame(height: 400)
                }

                // v2: Discovery "Show more" button (explicit, not auto-load)
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
            .padding(.vertical, Theme.spacingL)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

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
