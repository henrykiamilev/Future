import Foundation

// MARK: - Journal Service

/// Service for journal operations and streak tracking.
@MainActor
final class JournalService: ObservableObject {
    static let shared = JournalService()

    @Published private(set) var entries: [JournalEntry] = []
    @Published private(set) var journalMode: JournalMode?
    @Published private(set) var streakData: StreakData = StreakData()
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    private let apiClient = APIClient.shared
    private let userService = UserService.shared

    private init() {}

    // MARK: - Journal Mode

    /// Check if user has selected a journal mode.
    var hasSelectedMode: Bool {
        journalMode != nil
    }

    /// Set the journal mode (one-time choice, stored on user profile).
    func setJournalMode(_ mode: JournalMode) async throws {
        isLoading = true
        error = nil

        do {
            let request = SetJournalModeRequest(journalMode: mode)
            let _: UserProfileResponse = try await apiClient.post("/journal/mode", body: request)

            journalMode = mode
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Refresh journal mode from user profile.
    func refreshMode() async {
        // Get mode from user profile
        if let profile = userService.currentProfile {
            journalMode = profile.journalMode
        }
    }

    // MARK: - Entries

    /// Fetch journal entries.
    func fetchEntries(limit: Int = 30) async throws {
        isLoading = true
        error = nil

        do {
            let params = ["limit": "\(limit)"]
            let response: JournalEntriesResponse = try await apiClient.get("/journal/entries", queryParams: params)
            entries = response.entries.sorted { $0.entryDate > $1.entryDate }

            // Update streak data
            calculateStreakData()

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Create a new journal entry.
    func createEntry(content: String, for date: Date = Date(), prompt: String? = nil) async throws -> JournalEntry {
        guard let mode = journalMode else {
            throw JournalError.modeNotSelected
        }

        isLoading = true
        error = nil

        do {
            let request = CreateJournalEntryRequest(
                content: content,
                entryDate: date,
                mode: mode,
                promptUsed: prompt
            )

            let response: JournalEntryResponse = try await apiClient.post("/journal/entries", body: request)

            // Add to local list
            entries.insert(response.entry, at: 0)
            calculateStreakData()

            isLoading = false
            return response.entry
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Update an existing entry.
    func updateEntry(_ entryId: String, content: String) async throws -> JournalEntry {
        isLoading = true
        error = nil

        do {
            let request = UpdateJournalEntryRequest(content: content)
            let response: JournalEntryResponse = try await apiClient.put("/journal/entries/\(entryId)", body: request)

            if let index = entries.firstIndex(where: { $0.id == entryId }) {
                entries[index] = response.entry
            }

            isLoading = false
            return response.entry
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Delete an entry.
    func deleteEntry(_ entryId: String) async throws {
        isLoading = true
        error = nil

        do {
            try await apiClient.delete("/journal/entries/\(entryId)")
            entries.removeAll { $0.id == entryId }
            calculateStreakData()
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    // MARK: - Helpers

    /// Get entry for a specific date.
    func entry(for date: Date) -> JournalEntry? {
        let calendar = Calendar.current
        return entries.first { calendar.isDate($0.entryDate, inSameDayAs: date) }
    }

    /// Check if user has journaled today.
    var hasJournaledToday: Bool {
        entry(for: Date()) != nil
    }

    /// Get today's prompt (for guided mode).
    var todaysPrompt: String {
        GuidedPrompts.promptForDate(Date())
    }

    // MARK: - Streak Calculation

    private func calculateStreakData() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get unique journal dates
        let journalDates = Set(entries.map { calendar.startOfDay(for: $0.entryDate) })

        // Total entries
        let totalEntries = entries.count

        // Entries this month
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let entriesThisMonth = entries.filter { $0.entryDate >= startOfMonth }.count

        // Current streak (consecutive days ending today or yesterday)
        var currentStreak = 0
        var checkDate = today

        // Allow streak to continue if user journaled today or yesterday
        if !journalDates.contains(today) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               journalDates.contains(yesterday) {
                checkDate = yesterday
            }
        }

        while journalDates.contains(checkDate) {
            currentStreak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previousDay
        }

        // Longest streak
        var longestStreak = 0
        var tempStreak = 0
        let sortedDates = journalDates.sorted()

        for (index, date) in sortedDates.enumerated() {
            if index == 0 {
                tempStreak = 1
            } else {
                let previousDate = sortedDates[index - 1]
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: previousDate),
                   calendar.isDate(nextDay, inSameDayAs: date) {
                    tempStreak += 1
                } else {
                    tempStreak = 1
                }
            }
            longestStreak = max(longestStreak, tempStreak)
        }

        // Days since last entry
        var daysSinceLastEntry: Int? = nil
        if let lastEntry = entries.first {
            let lastDate = calendar.startOfDay(for: lastEntry.entryDate)
            daysSinceLastEntry = calendar.dateComponents([.day], from: lastDate, to: today).day
        }

        streakData = StreakData(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalEntries: totalEntries,
            entriesThisMonth: entriesThisMonth,
            daysSinceLastEntry: daysSinceLastEntry,
            hasJournaledToday: journalDates.contains(today)
        )
    }
}

// MARK: - Journal Error

enum JournalError: Error, LocalizedError {
    case modeNotSelected
    case entryNotFound

    var errorDescription: String? {
        switch self {
        case .modeNotSelected:
            return "Please select a journal mode first"
        case .entryNotFound:
            return "Entry not found"
        }
    }
}

// MARK: - Streak Data

struct StreakData {
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var totalEntries: Int = 0
    var entriesThisMonth: Int = 0
    var daysSinceLastEntry: Int? = nil
    var hasJournaledToday: Bool = false

    /// Forgiving message based on streak state.
    var encouragementMessage: String {
        if hasJournaledToday {
            return "You've reflected today. Well done."
        } else if let days = daysSinceLastEntry {
            if days == 0 {
                return "Ready when you are."
            } else if days == 1 {
                return "Welcome back. Ready to continue?"
            } else if days <= 3 {
                return "It's good to see you. Every entry counts."
            } else if days <= 7 {
                return "Welcome back. No pressure, just reflection."
            } else {
                return "Welcome back. The best time to start is now."
            }
        } else {
            return "Start your reflection journey today."
        }
    }

    /// Simple progress summary.
    var progressSummary: String {
        if totalEntries == 0 {
            return "Begin your first entry"
        } else if totalEntries == 1 {
            return "1 reflection so far"
        } else {
            return "\(totalEntries) reflections total"
        }
    }
}

// MARK: - API Models

struct SetJournalModeRequest: Encodable {
    let journalMode: JournalMode
}

struct CreateJournalEntryRequest: Encodable {
    let content: String
    let entryDate: Date
    let mode: JournalMode
    let promptUsed: String?
}

struct UpdateJournalEntryRequest: Encodable {
    let content: String
}

struct JournalEntriesResponse: Decodable {
    let entries: [JournalEntry]
}

struct JournalEntryResponse: Decodable {
    let entry: JournalEntry
}

struct UserProfileResponse: Decodable {
    let profile: UserProfile
}
