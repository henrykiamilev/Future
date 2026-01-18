import Foundation

class AIService {
    static let shared = AIService()
    private init() {}

    func refreshTokenStatus() async {
        do {
            let url = URL(string: "\(Config.backendURL)/api/ai/tokens")!
            let (_, _) = try await URLSession.shared.data(from: url)
        } catch {
            print("[AIService] Token refresh failed: \(error.localizedDescription)")
        }
    }
}
