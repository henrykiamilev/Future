import Foundation

// MARK: - Journal Entry

/// Daily journal entry for reflection.
/// User chooses once between free text or guided prompts (locked unless reset).
struct JournalEntry: Codable, Identifiable {
    let id: String
    let userId: String

    // Core content
    let entryDate: Date          // The day this entry is for
    var content: String          // The journal text

    // Mode (inherited from user preference)
    let mode: JournalMode

    // For guided prompts mode
    var promptUsed: String?      // The prompt that was shown

    // Metadata
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        entryDate: Date = Date(),
        content: String,
        mode: JournalMode,
        promptUsed: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.entryDate = entryDate
        self.content = content
        self.mode = mode
        self.promptUsed = promptUsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Convenience

extension JournalEntry {
    /// Check if this entry is for today
    var isToday: Bool {
        Calendar.current.isDateInToday(entryDate)
    }

    /// Formatted date for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: entryDate)
    }

    /// Returns a new JournalEntry with updated content
    func updating(content: String) -> JournalEntry {
        var updated = self
        updated.content = content
        updated.updatedAt = Date()
        return updated
    }

    /// Word count for the entry
    var wordCount: Int {
        content.split(separator: " ").count
    }
}

// MARK: - Guided Prompts

enum GuidedPrompts {
    static let prompts: [String] = [
        "What is one thing you accomplished today?",
        "What challenged you today, and how did you respond?",
        "What are you grateful for right now?",
        "What is one thing you learned today?",
        "How are you feeling about your progress?",
        "What would make tomorrow a good day?",
        "What is something you want to let go of?",
        "What gave you energy today?",
        "What drained your energy today?",
        "What is one small step you can take tomorrow?"
    ]

    /// Returns a random prompt
    static func randomPrompt() -> String {
        prompts.randomElement() ?? prompts[0]
    }

    /// Returns the prompt for a specific day (deterministic based on date)
    static func promptForDate(_ date: Date) -> String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        let index = dayOfYear % prompts.count
        return prompts[index]
    }
}
