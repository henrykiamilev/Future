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

// MARK: - Feed Endpoints

extension APIEndpoint {
    static func mainFeed(cursorScore: Double? = nil, cursorID: UUID? = nil, limit: Int = 20) -> APIEndpoint {
        var items: [URLQueryItem] = [.init(name: "limit", value: "\(limit)")]
        if let score = cursorScore { items.append(.init(name: "cursor_score", value: "\(score)")) }
        if let id = cursorID { items.append(.init(name: "cursor_id", value: id.uuidString)) }
        return APIEndpoint(path: "/feed/main", queryItems: items)
    }

    static func friendsFeed(cursor: Date? = nil, limit: Int = 20) -> APIEndpoint {
        var items: [URLQueryItem] = [.init(name: "limit", value: "\(limit)")]
        if let cursor {
            items.append(.init(name: "cursor", value: ISO8601DateFormatter().string(from: cursor)))
        }
        return APIEndpoint(path: "/feed/friends", queryItems: items)
    }

    static func recordExposures(authorIDs: [UUID]) -> APIEndpoint {
        APIEndpoint(path: "/feed/exposures", method: .POST, body: ExposureRequest(authorIds: authorIDs))
    }
}

// MARK: - Post Endpoints

extension APIEndpoint {
    static func createPost(_ request: CreatePostRequest) -> APIEndpoint {
        APIEndpoint(path: "/posts", method: .POST, body: request)
    }

    static func likePost(id: UUID) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.uuidString)/like", method: .POST)
    }

    static func unlikePost(id: UUID) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.uuidString)/like", method: .DELETE)
    }

    static func checkLiked(postIDs: [UUID]) -> APIEndpoint {
        let ids = postIDs.map(\.uuidString).joined(separator: ",")
        return APIEndpoint(
            path: "/posts/liked",
            queryItems: [.init(name: "ids", value: ids)]
        )
    }

    static func reportPost(id: UUID, reason: String) -> APIEndpoint {
        APIEndpoint(path: "/posts/\(id.uuidString)/report", method: .POST, body: ReportRequest(reason: reason))
    }
}

// MARK: - Profile Endpoints

extension APIEndpoint {
    static func profile(userID: UUID) -> APIEndpoint {
        APIEndpoint(path: "/users/\(userID.uuidString)/profile")
    }

    static func archive(cursor: Date? = nil, limit: Int = 20) -> APIEndpoint {
        var items: [URLQueryItem] = [.init(name: "limit", value: "\(limit)")]
        if let cursor {
            items.append(.init(name: "cursor", value: ISO8601DateFormatter().string(from: cursor)))
        }
        return APIEndpoint(path: "/me/archive", queryItems: items)
    }

    static func updateProfile(_ update: ProfileUpdate) -> APIEndpoint {
        APIEndpoint(path: "/me/profile", method: .PATCH, body: update)
    }
}

// MARK: - Signature Endpoints

extension APIEndpoint {
    static func addSignature(postID: UUID) -> APIEndpoint {
        APIEndpoint(path: "/me/signature/\(postID.uuidString)", method: .PUT)
    }

    static func removeSignature(postID: UUID) -> APIEndpoint {
        APIEndpoint(path: "/me/signature/\(postID.uuidString)", method: .DELETE)
    }
}

// MARK: - Follow Endpoints

extension APIEndpoint {
    static func follow(userID: UUID) -> APIEndpoint {
        APIEndpoint(path: "/users/\(userID.uuidString)/follow", method: .POST)
    }

    static func unfollow(userID: UUID) -> APIEndpoint {
        APIEndpoint(path: "/users/\(userID.uuidString)/follow", method: .DELETE)
    }
}

// MARK: - Settings Endpoints

extension APIEndpoint {
    static func updateVisibility(_ visibility: User.AccountVisibility) -> APIEndpoint {
        APIEndpoint(path: "/me/visibility", method: .PATCH, body: VisibilityUpdate(visibility: visibility))
    }

    static var deleteAccount: APIEndpoint {
        APIEndpoint(path: "/me", method: .DELETE)
    }
}

// MARK: - Image Upload

extension APIEndpoint {
    static var requestUploadURL: APIEndpoint {
        APIEndpoint(path: "/uploads/presign", method: .POST)
    }
}

// MARK: - Request Bodies

private struct ExposureRequest: Encodable, Sendable {
    let authorIds: [UUID]
}

private struct ReportRequest: Encodable, Sendable {
    let reason: String
}

struct ProfileUpdate: Encodable, Sendable {
    var displayName: String?
    var bio: String?
    var instagramHandle: String?
    var snapchatHandle: String?
}

private struct VisibilityUpdate: Encodable, Sendable {
    let visibility: User.AccountVisibility
}
