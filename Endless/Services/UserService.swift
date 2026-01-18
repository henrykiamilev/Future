import Foundation

class UserService {
    static let shared = UserService()
    private init() {}

    func syncUser() async throws -> Bool {
        let url = URL(string: "\(Config.backendURL)/api/users/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return true
    }
}
