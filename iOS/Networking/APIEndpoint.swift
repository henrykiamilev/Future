import Foundation

enum HTTPMethod: String, Sendable {
    case GET, POST, PUT, PATCH, DELETE
}

struct APIEndpoint: Sendable {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]
    let body: (any Encodable & Sendable)?

    init(
        path: String,
        method: HTTPMethod = .GET,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
    }
}

// ============================================================================
// SUPABASE RPC ENDPOINTS
// ============================================================================
// All database functions are called via POST /rest/v1/rpc/{function_name}
// with JSON body for parameters. Supabase PostgREST handles auth via JWT.
// ============================================================================

// MARK: - Feed Endpoints (Supabase RPC)

extension APIEndpoint {
    static func mainFeed(cursorScore: Double? = nil, cursorID: UUID? = nil, limit: Int = 20) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/get_main_feed",
            method: .POST,
            body: RPCMainFeed(
                p_cursor_score: cursorScore,
                p_cursor_id: cursorID?.uuidString,
                p_limit: limit
            )
        )
    }

    /// v2: Friends feed now uses ranked cursor (score, id) like main feed
    static func friendsFeed(cursorScore: Double? = nil, cursorID: UUID? = nil, limit: Int = 20) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/get_friends_feed",
            method: .POST,
            body: RPCFriendsFeedV2(
                p_cursor_score: cursorScore,
                p_cursor_id: cursorID?.uuidString,
                p_limit: limit
            )
        )
    }

    static func recordExposures(authorIDs: [UUID]) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/record_feed_exposures",
            method: .POST,
            body: RPCExposures(p_author_ids: authorIDs.map(\.uuidString))
        )
    }

    static func recordPostView(postID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/record_post_view",
            method: .POST,
            body: RPCPostView(p_post_id: postID.uuidString)
        )
    }
}

// MARK: - Post Endpoints (Supabase RPC)

extension APIEndpoint {
    static func createPost(_ request: CreatePostRequest) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/create_post",
            method: .POST,
            body: RPCCreatePost(
                p_image_url: request.imageURL,
                p_image_width: request.imageWidth,
                p_image_height: request.imageHeight,
                p_image_size_bytes: request.imageSizeBytes,
                p_tags: request.tags
            )
        )
    }

    static func likePost(id: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/like_post",
            method: .POST,
            body: RPCPostID(p_post_id: id.uuidString)
        )
    }

    static func unlikePost(id: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/unlike_post",
            method: .POST,
            body: RPCPostID(p_post_id: id.uuidString)
        )
    }

    static func checkLiked(postIDs: [UUID]) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/check_liked_posts",
            method: .POST,
            body: RPCCheckLiked(p_post_ids: postIDs.map(\.uuidString))
        )
    }

    static func reportPost(id: UUID, reason: String) -> APIEndpoint {
        // Uses RPC to auto-set reporter_id from auth.uid() and prevent duplicates
        APIEndpoint(
            path: "/rest/v1/rpc/report_content",
            method: .POST,
            body: RPCReport(p_target_type: "post", p_target_id: id.uuidString, p_reason: reason)
        )
    }
}

// MARK: - Profile Endpoints (Supabase RPC)

extension APIEndpoint {
    static func profile(userID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/get_user_profile",
            method: .POST,
            body: RPCUserID(p_user_id: userID.uuidString)
        )
    }

    static func archive(cursor: Date? = nil, limit: Int = 20) -> APIEndpoint {
        var cursorString: String?
        if let cursor {
            cursorString = ISO8601DateFormatter().string(from: cursor)
        }
        return APIEndpoint(
            path: "/rest/v1/rpc/get_user_archive",
            method: .POST,
            body: RPCArchive(p_cursor: cursorString, p_limit: limit)
        )
    }

    static func updateProfile(_ update: ProfileUpdate, userID: UUID) -> APIEndpoint {
        // Direct table update via PostgREST — RLS ensures own-row only
        APIEndpoint(
            path: "/rest/v1/users",
            method: .PATCH,
            queryItems: [.init(name: "id", value: "eq.\(userID.uuidString)")],
            body: update
        )
    }
}

// MARK: - Signature Endpoints (Supabase RPC)

extension APIEndpoint {
    static func addSignature(postID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/add_to_signature",
            method: .POST,
            body: RPCPostID(p_post_id: postID.uuidString)
        )
    }

    static func removeSignature(postID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/remove_from_signature",
            method: .POST,
            body: RPCPostID(p_post_id: postID.uuidString)
        )
    }
}

// MARK: - Follow Endpoints (Supabase PostgREST)

extension APIEndpoint {
    static func follow(userID: UUID, currentUserID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/follows",
            method: .POST,
            body: RPCFollow(follower_id: currentUserID.uuidString, following_id: userID.uuidString)
        )
    }

    static func unfollow(userID: UUID, currentUserID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/follows",
            method: .DELETE,
            queryItems: [
                .init(name: "follower_id", value: "eq.\(currentUserID.uuidString)"),
                .init(name: "following_id", value: "eq.\(userID.uuidString)")
            ]
        )
    }
}

// MARK: - Settings Endpoints

extension APIEndpoint {
    static func updateVisibility(_ visibility: User.AccountVisibility, userID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/users",
            method: .PATCH,
            queryItems: [.init(name: "id", value: "eq.\(userID.uuidString)")],
            body: VisibilityUpdate(visibility: visibility)
        )
    }

    static var deleteAccount: APIEndpoint {
        APIEndpoint(path: "/rest/v1/rpc/delete_own_account", method: .POST)
    }
}

// MARK: - Signature Queries

extension APIEndpoint {
    static func signaturePosts(userID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/get_signature_posts",
            method: .POST,
            body: RPCUserID(p_user_id: userID.uuidString)
        )
    }
}

// MARK: - Search Endpoints

extension APIEndpoint {
    static func searchUsers(query: String, limit: Int = 20) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/search_users",
            method: .POST,
            body: RPCSearch(p_query: query, p_limit: limit)
        )
    }
}

// MARK: - Discover Endpoints

extension APIEndpoint {
    static func suggestedUsers(limit: Int = 10) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/get_suggested_users",
            method: .POST,
            body: RPCLimit(p_limit: limit)
        )
    }

    static func explorePosts(limit: Int = 10) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/get_explore_posts",
            method: .POST,
            body: RPCLimit(p_limit: limit)
        )
    }
}

// MARK: - Consumption Tracking Endpoints

extension APIEndpoint {
    /// v2: Record post consumption for finite feed tracking
    static func recordConsumption(postID: UUID, feedType: String) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/record_post_consumption",
            method: .POST,
            body: RPCConsumption(p_post_id: postID.uuidString, p_feed_type: feedType)
        )
    }
}

// MARK: - Comment Endpoints

extension APIEndpoint {
    static func getComments(postID: UUID, cursor: Date? = nil, limit: Int = 30) -> APIEndpoint {
        var cursorString: String?
        if let cursor {
            cursorString = ISO8601DateFormatter().string(from: cursor)
        }
        return APIEndpoint(
            path: "/rest/v1/rpc/get_post_comments",
            method: .POST,
            body: RPCGetComments(
                p_post_id: postID.uuidString,
                p_cursor: cursorString,
                p_limit: limit
            )
        )
    }

    static func addComment(postID: UUID, content: String) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/add_comment",
            method: .POST,
            body: RPCAddComment(p_post_id: postID.uuidString, p_content: content)
        )
    }

    static func deleteComment(commentID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/delete_comment",
            method: .POST,
            body: RPCCommentID(p_comment_id: commentID.uuidString)
        )
    }
}

// MARK: - Followers / Following List Endpoints

extension APIEndpoint {
    static func followers(userID: UUID, limit: Int = 50) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/get_followers",
            method: .POST,
            body: RPCFollowList(p_user_id: userID.uuidString, p_limit: limit)
        )
    }

    static func following(userID: UUID, limit: Int = 50) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/get_following",
            method: .POST,
            body: RPCFollowList(p_user_id: userID.uuidString, p_limit: limit)
        )
    }
}

// MARK: - Settings Endpoints (extended)

extension APIEndpoint {
    static func updateCommentsEnabled(_ enabled: Bool, userID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/users",
            method: .PATCH,
            queryItems: [.init(name: "id", value: "eq.\(userID.uuidString)")],
            body: CommentsEnabledUpdate(comments_enabled: enabled)
        )
    }

    static func updateProfilePhoto(url: String, userID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/users",
            method: .PATCH,
            queryItems: [.init(name: "id", value: "eq.\(userID.uuidString)")],
            body: ProfilePhotoUpdate(profile_photo_url: url)
        )
    }

    static func updateProfileTheme(_ theme: String, userID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/users",
            method: .PATCH,
            queryItems: [.init(name: "id", value: "eq.\(userID.uuidString)")],
            body: ProfileThemeUpdate(profile_theme: theme)
        )
    }
}

// MARK: - Push Notification Endpoints

extension APIEndpoint {
    static func registerPushToken(_ token: String) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/register_push_token",
            method: .POST,
            body: RPCPushToken(p_token: token, p_platform: "ios")
        )
    }
}

// MARK: - Notification Center Endpoints

extension APIEndpoint {
    static func notifications(cursor: Date? = nil, limit: Int = 30) -> APIEndpoint {
        var cursorString: String?
        if let cursor {
            cursorString = ISO8601DateFormatter().string(from: cursor)
        }
        return APIEndpoint(
            path: "/rest/v1/rpc/get_notifications",
            method: .POST,
            body: RPCNotifications(p_cursor: cursorString, p_limit: limit)
        )
    }

    static var markNotificationsRead: APIEndpoint {
        APIEndpoint(path: "/rest/v1/rpc/mark_notifications_read", method: .POST)
    }

    static var unreadNotificationCount: APIEndpoint {
        APIEndpoint(path: "/rest/v1/rpc/get_unread_notification_count", method: .POST)
    }
}

// MARK: - Reaction Endpoints

extension APIEndpoint {
    static func reactToPost(postID: UUID, emoji: String) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/react_to_post",
            method: .POST,
            body: RPCReaction(p_post_id: postID.uuidString, p_emoji: emoji)
        )
    }

    static func removeReaction(postID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/remove_reaction",
            method: .POST,
            body: RPCPostID(p_post_id: postID.uuidString)
        )
    }

    static func getPostReactions(postIDs: [UUID]) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/rpc/get_post_reactions",
            method: .POST,
            body: RPCReactionCheck(p_post_ids: postIDs.map(\.uuidString))
        )
    }
}

// MARK: - Onboarding Endpoints

extension APIEndpoint {
    static func completeOnboarding(userID: UUID) -> APIEndpoint {
        APIEndpoint(
            path: "/rest/v1/users",
            method: .PATCH,
            queryItems: [.init(name: "id", value: "eq.\(userID.uuidString)")],
            body: OnboardingComplete(onboardingCompletedAt: Date())
        )
    }
}

// MARK: - Supabase RPC Request Bodies

private struct RPCMainFeed: Encodable, Sendable {
    let p_cursor_score: Double?
    let p_cursor_id: String?
    let p_limit: Int
}

/// v2: Friends feed now uses ranked cursor (score, id)
private struct RPCFriendsFeedV2: Encodable, Sendable {
    let p_cursor_score: Double?
    let p_cursor_id: String?
    let p_limit: Int
}

private struct RPCConsumption: Encodable, Sendable {
    let p_post_id: String
    let p_feed_type: String
}

private struct RPCExposures: Encodable, Sendable {
    let p_author_ids: [String]
}

private struct RPCPostView: Encodable, Sendable {
    let p_post_id: String
}

private struct RPCCreatePost: Encodable, Sendable {
    let p_image_url: String
    let p_image_width: Int
    let p_image_height: Int
    let p_image_size_bytes: Int
    let p_tags: [TagInput]
}

private struct RPCPostID: Encodable, Sendable {
    let p_post_id: String
}

private struct RPCCheckLiked: Encodable, Sendable {
    let p_post_ids: [String]
}

private struct RPCReport: Encodable, Sendable {
    let p_target_type: String
    let p_target_id: String
    let p_reason: String
}

private struct RPCUserID: Encodable, Sendable {
    let p_user_id: String
}

private struct RPCArchive: Encodable, Sendable {
    let p_cursor: String?
    let p_limit: Int
}

private struct RPCFollow: Encodable, Sendable {
    let follower_id: String
    let following_id: String
}

struct ProfileUpdate: Encodable, Sendable {
    var displayName: String
    var bio: String
    var instagramHandle: String
    var snapchatHandle: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case bio
        case instagramHandle = "instagram_handle"
        case snapchatHandle = "snapchat_handle"
    }
}

private struct VisibilityUpdate: Encodable, Sendable {
    let visibility: User.AccountVisibility
}

private struct RPCSearch: Encodable, Sendable {
    let p_query: String
    let p_limit: Int
}

private struct RPCLimit: Encodable, Sendable {
    let p_limit: Int
}

private struct RPCGetComments: Encodable, Sendable {
    let p_post_id: String
    let p_cursor: String?
    let p_limit: Int
}

private struct RPCAddComment: Encodable, Sendable {
    let p_post_id: String
    let p_content: String
}

private struct RPCCommentID: Encodable, Sendable {
    let p_comment_id: String
}

private struct RPCFollowList: Encodable, Sendable {
    let p_user_id: String
    let p_limit: Int
}

private struct CommentsEnabledUpdate: Encodable, Sendable {
    let comments_enabled: Bool
}

private struct ProfilePhotoUpdate: Encodable, Sendable {
    let profile_photo_url: String
}

private struct ProfileThemeUpdate: Encodable, Sendable {
    let profile_theme: String
}

private struct RPCPushToken: Encodable, Sendable {
    let p_token: String
    let p_platform: String
}

private struct OnboardingComplete: Encodable, Sendable {
    let onboardingCompletedAt: Date
}

private struct RPCNotifications: Encodable, Sendable {
    let p_cursor: String?
    let p_limit: Int
}

private struct RPCReaction: Encodable, Sendable {
    let p_post_id: String
    let p_emoji: String
}

private struct RPCReactionCheck: Encodable, Sendable {
    let p_post_ids: [String]
}
