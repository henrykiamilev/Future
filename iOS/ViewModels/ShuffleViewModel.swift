import Foundation

enum ShuffleAction: String, Sendable {
    case followed
    case skipped
    case saved
}

@MainActor
final class ShuffleViewModel: ObservableObject {

    @Published var cards: [ShuffleCard] = []
    @Published var isExhausted = false
    @Published var itemsRemaining: Int = 0
    @Published var isLoading = false
    @Published var error: String?

    // Session stats
    @Published var followedCount: Int = 0
    @Published var savedCount: Int = 0

    private let shuffleService: ShuffleServiceProtocol
    private var hasLoadedInitial = false

    init(shuffleService: ShuffleServiceProtocol) {
        self.shuffleService = shuffleService
    }

    func loadDeck() async {
        guard !hasLoadedInitial else { return }
        isLoading = true
        error = nil

        do {
            let response = try await shuffleService.fetchDeck(limit: 20)
            cards = response.cards
            isExhausted = response.isExhausted
            itemsRemaining = response.itemsRemaining
            hasLoadedInitial = true
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func reloadDeck() async {
        hasLoadedInitial = false
        await loadDeck()
    }

    func swipe(_ action: ShuffleAction) {
        guard !cards.isEmpty else { return }

        let card = cards.first!

        // Remove top card immediately for snappy UI
        cards.removeFirst()

        // Update session stats
        switch action {
        case .followed: followedCount += 1
        case .saved: savedCount += 1
        case .skipped: break
        }

        // Update remaining count
        if itemsRemaining > 0 {
            itemsRemaining -= 1
        }
        if cards.isEmpty && itemsRemaining <= 0 {
            isExhausted = true
        }

        // Fire-and-forget API call
        Task {
            do {
                try await shuffleService.recordAction(
                    targetUserID: card.id,
                    action: action.rawValue
                )
            } catch {
                #if DEBUG
                print("[ShuffleVM] Failed to record action: \(error)")
                #endif
            }
        }

        // Load more if running low
        if cards.count <= 3 && !isExhausted {
            Task { await loadMore() }
        }
    }

    private func loadMore() async {
        guard !isExhausted else { return }
        do {
            let response = try await shuffleService.fetchDeck(limit: 10)
            // Append only new cards (avoid duplicates)
            let existingIDs = Set(cards.map(\.id))
            let newCards = response.cards.filter { !existingIDs.contains($0.id) }
            cards.append(contentsOf: newCards)
            isExhausted = response.isExhausted
            itemsRemaining = response.itemsRemaining
        } catch {
            #if DEBUG
            print("[ShuffleVM] Load more failed: \(error)")
            #endif
        }
    }
}
