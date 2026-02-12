import Foundation

struct Tag: Codable, Identifiable, Equatable, Sendable {
    var id: String { label }
    let label: String
    let externalURL: String?
    let positionX: Float?
    let positionY: Float?

    enum CodingKeys: String, CodingKey {
        case label
        case externalURL = "externalUrl"
        case positionX
        case positionY
    }
}

struct TagInput: Encodable, Sendable {
    let label: String
    let externalURL: String?

    enum CodingKeys: String, CodingKey {
        case label
        case externalURL = "externalUrl"
    }
}
