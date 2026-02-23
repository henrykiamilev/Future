import Foundation
import UserNotifications
import UIKit

final class NotificationService: NSObject, Sendable {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    // MARK: - Request Permission

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Register Token

    func registerDeviceToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        do {
            try await client.requestVoid(.registerPushToken(token))
        } catch {
            // Silently fail — will retry on next app launch
        }
    }

    // MARK: - Notification Center

    func fetchNotifications(cursor: Date? = nil) async throws -> [AppNotification] {
        try await client.request(.notifications(cursor: cursor))
    }

    func markAllRead() async {
        try? await client.requestVoid(.markNotificationsRead)
    }

    func fetchUnreadCount() async -> Int {
        do {
            let count: Int = try await client.request(.unreadNotificationCount)
            return count
        } catch {
            return 0
        }
    }
}
