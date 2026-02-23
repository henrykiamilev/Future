import SwiftUI

struct NotificationView: View {

    @StateObject var viewModel: NotificationViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.notifications.isEmpty {
                loadingView
            } else if viewModel.notifications.isEmpty {
                emptyView
            } else {
                notificationList
            }
        }
        .background(Theme.background)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadInitial()
            await viewModel.markAllRead()
        }
    }

    // MARK: - List

    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.notifications) { notification in
                    NotificationRow(notification: notification)
                        .task {
                            if notification.id == viewModel.notifications.last?.id {
                                await viewModel.loadMore()
                            }
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

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Image(systemName: "bell")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Theme.textTertiary)

            Text("No activity yet")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)

            Text("When people like, comment, or follow you, it'll show up here.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)
            Spacer()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(Theme.textTertiary)
            Spacer()
        }
    }
}

// MARK: - Notification Row

struct NotificationRow: View {

    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingS) {
            // Actor avatar
            CachedImageView(
                url: SupabaseConfig.storageURL(for: notification.actorPhoto ?? ""),
                targetSize: CGSize(width: 80, height: 80)
            ) {
                Circle()
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.actorUsername)
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                +
                Text(" \(notification.message)")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)

                Text(notification.createdAt.timeAgo())
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()

            // Post thumbnail (for like/comment notifications)
            if let imageURL = notification.postImageUrl {
                CachedImageView(
                    url: SupabaseConfig.storageURL(for: imageURL),
                    targetSize: CGSize(width: 88, height: 88)
                ) {
                    RoundedRectangle(cornerRadius: Theme.radiusS)
                        .fill(Theme.separator)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
            } else {
                // Follow icon for follow notifications
                Image(systemName: notification.systemIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
        .background(notification.isRead ? Color.clear : Theme.background.opacity(0.5))
    }
}
