import Foundation
import Combine

enum SearchMode: String, CaseIterable, Sendable {
    case shuffle = "Shuffle"
    case browse = "Browse"
}

@MainActor
final class SearchViewModel: ObservableObject {

    @Published var query: String = ""
    @Published private(set) var results: [UserSummary] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false
    @Published private(set) var error: String?

    // Mode toggle
    @Published var mode: SearchMode = .shuffle

    // Discover state
    @Published private(set) var suggestedUsers: [SuggestedUser] = []
    @Published private(set) var explorePosts: [ExplorePost] = []
    @Published private(set) var isLoadingDiscover = false
    private var hasLoadedDiscover = false

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

    // MARK: - Discover

    func loadDiscover() async {
        guard !hasLoadedDiscover else { return }
        isLoadingDiscover = true

        async let users = searchService.fetchSuggestedUsers(limit: 10)
        async let posts = searchService.fetchExplorePosts(limit: 30)

        do {
            suggestedUsers = try await users
        } catch {
            suggestedUsers = []
        }

        do {
            explorePosts = try await posts
        } catch {
            explorePosts = []
        }

        hasLoadedDiscover = true
        isLoadingDiscover = false
    }
}
