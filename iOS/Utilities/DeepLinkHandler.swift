import UIKit

enum DeepLinkHandler {

    // MARK: - Handle Validation

    /// Validates that a social media handle contains only safe characters.
    private static func isValidHandle(_ handle: String) -> Bool {
        !handle.isEmpty && handle.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
    }

    // MARK: - Instagram
    // Deep link to Instagram app, fallback to web profile.

    static func openInstagram(handle: String) {
        guard isValidHandle(handle),
              let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }

        // Use the universal link — iOS will open the Instagram app directly
        // if it's installed, otherwise it falls back to Safari.
        let universalURL = URL(string: "https://www.instagram.com/\(encoded)")

        if let url = universalURL {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Snapchat
    // Deep link to Snapchat app, fallback to web profile.

    static func openSnapchat(handle: String) {
        guard isValidHandle(handle),
              let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }

        // Use the universal link — iOS will open the Snapchat app directly
        // if it's installed, otherwise it falls back to Safari.
        let universalURL = URL(string: "https://www.snapchat.com/add/\(encoded)")

        if let url = universalURL {
            UIApplication.shared.open(url)
        }
    }
}
