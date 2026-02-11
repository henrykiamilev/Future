import UIKit

enum DeepLinkHandler {

    // MARK: - Instagram
    // Deep link to Instagram app, fallback to web profile.

    static func openInstagram(handle: String) {
        let appURL = URL(string: "instagram://user?username=\(handle)")
        let webURL = URL(string: "https://instagram.com/\(handle)")

        open(appURL: appURL, webFallback: webURL)
    }

    // MARK: - Snapchat
    // Deep link to Snapchat app, fallback to web profile.

    static func openSnapchat(handle: String) {
        let appURL = URL(string: "snapchat://add/\(handle)")
        let webURL = URL(string: "https://snapchat.com/add/\(handle)")

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
