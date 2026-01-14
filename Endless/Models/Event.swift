import Foundation

// MARK: - Event Source

enum EventSource: String, Codable {
    case manual      // Created by user
    case aiGenerated // Created by AI planning engine
}

// MARK: - Event

struct Event: Codable, Identifiable {
    let id: String
    let userId: String
    let planId: String?

    // Core properties
    var title: String
    var description: String?

    // Time (day-locked: can move within day, not to another day)
    let scheduledDate: Date      // The day this event is locked to
    var startTime: Date          // Can be adjusted within scheduledDate
    var endTime: Date            // Can be adjusted within scheduledDate

    // Location
    var location: String?

    // Source and editability
    let source: EventSource

    // AI-specific context (only for aiGenerated)
    var purpose: String?         // Why this advances the user's goal
    var explanation: String?     // Detailed paragraph from AI

    // State
    var isCompleted: Bool

    // Metadata
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        planId: String? = nil,
        title: String,
        description: String? = nil,
        scheduledDate: Date,
        startTime: Date,
        endTime: Date,
        location: String? = nil,
        source: EventSource = .manual,
        purpose: String? = nil,
        explanation: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.planId = planId
        self.title = title
        self.description = description
        self.scheduledDate = scheduledDate
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.source = source
        self.purpose = purpose
        self.explanation = explanation
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Convenience

extension Event {
    /// Events can have their time adjusted, but only within the same day
    var canAdjustTime: Bool {
        true
    }

    /// Manual events can be fully edited; AI events have restricted editing
    var canEditDetails: Bool {
        source == .manual
    }

    /// Only manual events can be deleted
    var canDelete: Bool {
        source == .manual
    }

    /// Duration in minutes
    var durationMinutes: Int {
        let interval = endTime.timeIntervalSince(startTime)
        return Int(interval / 60)
    }

    /// Check if a proposed time adjustment stays within the scheduled date
    func canAdjustTo(newStartTime: Date, newEndTime: Date) -> Bool {
        let calendar = Calendar.current
        let scheduledDay = calendar.startOfDay(for: scheduledDate)
        let newStartDay = calendar.startOfDay(for: newStartTime)
        let newEndDay = calendar.startOfDay(for: newEndTime)

        return newStartDay == scheduledDay && newEndDay == scheduledDay
    }

    /// Returns a new Event with adjusted times (if valid)
    func adjustingTime(newStartTime: Date, newEndTime: Date) -> Event? {
        guard canAdjustTo(newStartTime: newStartTime, newEndTime: newEndTime) else {
            return nil
        }

        var updated = self
        updated.startTime = newStartTime
        updated.endTime = newEndTime
        updated.updatedAt = Date()
        return updated
    }

    /// Returns a new Event marked as completed
    func completing() -> Event {
        var updated = self
        updated.isCompleted = true
        updated.updatedAt = Date()
        return updated
    }
}
