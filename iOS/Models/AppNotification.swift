import Foundation

struct AppNotification: Decodable, Identifiable, Sendable {
    let id: UUID
    let type: NotificationType
    let actorId: UUID
    let actorUsername: String
    let actorPhoto: String?
    let postId: UUID?
    let postImageUrl: String?
    let commentPreview: String?
    let isRead: Bool
    let createdAt: Date

    enum NotificationType: String, Decodable, Sendable {
        case like
        case follow
        case comment
    }

    var message: String {
        switch type {
        case .like:
            return "liked your post"
        case .follow:
            return "started following you"
        case .comment:
            if let preview = commentPreview, !preview.isEmpty {
                return "commented: \(preview)"
            }
            return "commented on your post"
        }
    }

    var systemIcon: String {
        switch type {
        case .like: return "heart.fill"
        case .follow: return "person.badge.plus"
        case .comment: return "bubble.right.fill"
        }
    }
}
