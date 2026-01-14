import Foundation

// MARK: - Plan Status

enum PlanStatus: String, Codable {
    case active      // Currently active plan
    case modified    // Plan has been adjusted
    case archived    // Replaced by a new plan
}

// MARK: - Plan

/// Container for AI-generated planning content.
/// Stores the original user input, AI response, and modification history.
struct Plan: Codable, Identifiable {
    let id: String
    let userId: String

    // User input that generated this plan
    let userInput: UserGoalInput

    // Plan state
    var status: PlanStatus

    // Generated content summary
    var summary: String?         // Brief description of what the plan covers

    // Modification tracking (supports "adapt, don't break")
    var modificationHistory: [PlanModification]
    var lastModifiedAt: Date?

    // Metadata
    let generatedAt: Date
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        userInput: UserGoalInput,
        status: PlanStatus = .active,
        summary: String? = nil,
        modificationHistory: [PlanModification] = [],
        lastModifiedAt: Date? = nil,
        generatedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.userInput = userInput
        self.status = status
        self.summary = summary
        self.modificationHistory = modificationHistory
        self.lastModifiedAt = lastModifiedAt
        self.generatedAt = generatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - User Goal Input

/// Captures what the user shared during AI goal intake
struct UserGoalInput: Codable {
    let rawText: String              // Full text user entered
    var goal: String?                // Extracted: what they want to achieve
    var background: String?          // Extracted: school, experience, etc.
    var strengths: String?           // Extracted: what they're confident in
    var weaknesses: String?          // Extracted: areas of struggle
    var timeline: String?            // Extracted: urgency or deadline
    var additionalContext: String?   // Any other relevant info

    init(
        rawText: String,
        goal: String? = nil,
        background: String? = nil,
        strengths: String? = nil,
        weaknesses: String? = nil,
        timeline: String? = nil,
        additionalContext: String? = nil
    ) {
        self.rawText = rawText
        self.goal = goal
        self.background = background
        self.strengths = strengths
        self.weaknesses = weaknesses
        self.timeline = timeline
        self.additionalContext = additionalContext
    }
}

// MARK: - Plan Modification

/// Tracks changes made to a plan over time
struct PlanModification: Codable, Identifiable {
    let id: String
    let modifiedAt: Date
    let modificationType: ModificationType
    let description: String

    init(
        id: String = UUID().uuidString,
        modifiedAt: Date = Date(),
        modificationType: ModificationType,
        description: String
    ) {
        self.id = id
        self.modifiedAt = modifiedAt
        self.modificationType = modificationType
        self.description = description
    }
}

enum ModificationType: String, Codable {
    case adjustment      // Minor tweaks (default AI behavior)
    case restructure     // Full replan (requires explicit language)
    case userEdit        // Manual user changes
}

// MARK: - Convenience

extension Plan {
    /// Check if this is the user's active plan
    var isActive: Bool {
        status == .active
    }

    /// Number of times this plan has been modified
    var modificationCount: Int {
        modificationHistory.count
    }

    /// Returns a new Plan with added modification record
    func addingModification(_ modification: PlanModification) -> Plan {
        var updated = self
        updated.modificationHistory.append(modification)
        updated.lastModifiedAt = modification.modifiedAt
        updated.status = .modified
        updated.updatedAt = Date()
        return updated
    }

    /// Returns a new Plan marked as archived
    func archiving() -> Plan {
        var updated = self
        updated.status = .archived
        updated.updatedAt = Date()
        return updated
    }
}
