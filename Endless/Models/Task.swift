import Foundation

// MARK: - Task Source

enum TaskSource: String, Codable {
    case manual      // Created by user
    case aiGenerated // Created by AI planning engine
}

// MARK: - Task

/// Tasks are flexible items that users can freely schedule, edit, or delete.
/// Unlike Events, Tasks are not locked to a specific day.
struct Task: Codable, Identifiable {
    let id: String
    let userId: String
    let planId: String?

    // Core properties
    var title: String
    var description: String?

    // Flexible scheduling (user decides when)
    var scheduledDate: Date?     // Optional: user may schedule later
    var scheduledTime: Date?     // Optional: specific time if user sets one
    var estimatedMinutes: Int?   // Suggested duration

    // Source tracking
    let source: TaskSource

    // AI-specific context (only for aiGenerated)
    var purpose: String?         // Why this advances the user's goal
    var explanation: String?     // Detailed paragraph from AI

    // State
    var isCompleted: Bool
    var completedAt: Date?

    // Metadata
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        planId: String? = nil,
        title: String,
        description: String? = nil,
        scheduledDate: Date? = nil,
        scheduledTime: Date? = nil,
        estimatedMinutes: Int? = nil,
        source: TaskSource = .manual,
        purpose: String? = nil,
        explanation: String? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.planId = planId
        self.title = title
        self.description = description
        self.scheduledDate = scheduledDate
        self.scheduledTime = scheduledTime
        self.estimatedMinutes = estimatedMinutes
        self.source = source
        self.purpose = purpose
        self.explanation = explanation
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Convenience

extension Task {
    /// Tasks are fully flexible - can always be edited
    var canEdit: Bool {
        true
    }

    /// Tasks can always be deleted (unlike day-locked events)
    var canDelete: Bool {
        true
    }

    /// Tasks can be rescheduled to any date
    var canReschedule: Bool {
        true
    }

    /// Check if task is scheduled
    var isScheduled: Bool {
        scheduledDate != nil
    }

    /// Check if task is overdue (scheduled but not completed, past date)
    var isOverdue: Bool {
        guard let scheduled = scheduledDate, !isCompleted else { return false }
        return scheduled < Calendar.current.startOfDay(for: Date())
    }

    /// Returns a new Task with updated schedule
    func scheduling(date: Date?, time: Date? = nil) -> Task {
        var updated = self
        updated.scheduledDate = date
        updated.scheduledTime = time
        updated.updatedAt = Date()
        return updated
    }

    /// Returns a new Task marked as completed
    func completing() -> Task {
        var updated = self
        updated.isCompleted = true
        updated.completedAt = Date()
        updated.updatedAt = Date()
        return updated
    }

    /// Returns a new Task marked as incomplete
    func uncompleting() -> Task {
        var updated = self
        updated.isCompleted = false
        updated.completedAt = nil
        updated.updatedAt = Date()
        return updated
    }

    /// Returns a new Task with edited content
    func editing(title: String? = nil, description: String? = nil) -> Task {
        var updated = self
        if let title = title {
            updated.title = title
        }
        if let description = description {
            updated.description = description
        }
        updated.updatedAt = Date()
        return updated
    }
}
