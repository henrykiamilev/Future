import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {

    @Published var query: String = ""
    @Published private(set) var results: [UserSummary] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false
    @Published private(set) var error: String?

    private let searchService: SearchServiceProtocol
    private var debounceTask: Task<Void, Never>?

    init(searchService: SearchServiceProtocol) {
        self.searchService = searchService
    }

    func onQueryChanged() {
        debounceTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard trimmed.count >= 2 else {
            results = []
            hasSearched = false
            return
        }

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    func search(_ text: String) async {
        isSearching = true
        error = nil
        do {
            results = try await searchService.searchUsers(query: text, limit: 20)
        } catch {
            results = []
            self.error = error.localizedDescription
        }
        hasSearched = true
        isSearching = false
    }
}
