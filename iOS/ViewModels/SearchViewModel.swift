import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {

    @Published var query: String = ""
    @Published private(set) var results: [UserSummary] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false

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
        do {
            results = try await searchService.searchUsers(query: text, limit: 20)
        } catch {
            results = []
        }
        hasSearched = true
        isSearching = false
    }
}
