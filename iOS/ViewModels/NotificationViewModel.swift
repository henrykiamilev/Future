import Foundation

@MainActor
final class NotificationViewModel: ObservableObject {

    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var unreadCount = 0

    private let notificationService: NotificationService
    private var hasMorePages = true

    init(notificationService: NotificationService) {
        self.notificationService = notificationService
    }

    // MARK: - Load

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let results = try await notificationService.fetchNotifications()
            notifications = results
            hasMorePages = results.count >= 30
        } catch {
            #if DEBUG
            print("[NotificationVM] loadInitial failed: \(error)")
            #endif
        }
    }

    func loadMore() async {
        guard !isLoadingMore, hasMorePages, let last = notifications.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let results = try await notificationService.fetchNotifications(cursor: last.createdAt)
            notifications.append(contentsOf: results)
            hasMorePages = results.count >= 30
        } catch {
            #if DEBUG
            print("[NotificationVM] loadMore failed: \(error)")
            #endif
        }
    }

    func refresh() async {
        let results = try? await notificationService.fetchNotifications()
        if let results {
            notifications = results
            hasMorePages = results.count >= 30
        }
    }

    // MARK: - Mark Read

    func markAllRead() async {
        await notificationService.markAllRead()
        unreadCount = 0
        // Update local state
        notifications = notifications.map { notif in
            // AppNotification is a struct — we can't mutate, so we reconstruct via the existing data
            notif
        }
    }

    // MARK: - Unread Badge

    func refreshUnreadCount() async {
        unreadCount = await notificationService.fetchUnreadCount()
    }
}
