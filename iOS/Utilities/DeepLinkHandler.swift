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
        let appURL = URL(string: "instagram://user?username=\(encoded)")
        let webURL = URL(string: "https://instagram.com/\(encoded)")

        open(appURL: appURL, webFallback: webURL)
    }

    // MARK: - Snapchat
    // Deep link to Snapchat app, fallback to web profile.

    static func openSnapchat(handle: String) {
        guard isValidHandle(handle),
              let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        let appURL = URL(string: "snapchat://add/\(encoded)")
        let webURL = URL(string: "https://snapchat.com/add/\(encoded)")

        open(appURL: appURL, webFallback: webURL)
    }

    // MARK: - Generic Open

    private static func open(appURL: URL?, webFallback: URL?) {
        guard let appURL else {
            if let webFallback { UIApplication.shared.open(webFallback) }
            return
        }

        UIApplication.shared.open(appURL, options: [:]) { opened in
            if !opened, let webFallback {
                UIApplication.shared.open(webFallback)
            }
        }
    }
}
