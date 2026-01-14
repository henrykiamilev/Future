import Foundation

// MARK: - Calendar Service

/// Service for calendar data operations via backend API.
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var events: [Event] = []
    @Published private(set) var tasks: [Task] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Fetch Data

    /// Fetch events for a date range.
    func fetchEvents(from startDate: Date, to endDate: Date) async throws {
        isLoading = true
        error = nil

        do {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]

            let params = [
                "start_date": formatter.string(from: startDate),
                "end_date": formatter.string(from: endDate)
            ]

            let response: EventsResponse = try await apiClient.get("/calendar/events", queryParams: params)
            events = response.events
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Fetch tasks (optionally filtered by date).
    func fetchTasks(for date: Date? = nil) async throws {
        isLoading = true
        error = nil

        do {
            var params: [String: String] = [:]
            if let date = date {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                params["date"] = formatter.string(from: date)
            }

            let response: TasksResponse = try await apiClient.get("/calendar/tasks", queryParams: params)
            tasks = response.tasks
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Fetch all calendar data for a week.
    func fetchWeek(containing date: Date) async {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!

        do {
            try await fetchEvents(from: weekStart, to: weekEnd)
            try await fetchTasks(for: nil)
        } catch {
            print("[CalendarService] Failed to fetch week: \(error)")
        }
    }

    // MARK: - Create

    /// Create a new manual event.
    func createEvent(_ request: CreateEventRequest) async throws -> Event {
        isLoading = true
        error = nil

        do {
            let response: EventResponse = try await apiClient.post("/calendar/events", body: request)
            events.append(response.event)
            isLoading = false
            return response.event
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Create a new manual task.
    func createTask(_ request: CreateTaskRequest) async throws -> Task {
        isLoading = true
        error = nil

        do {
            let response: TaskResponse = try await apiClient.post("/calendar/tasks", body: request)
            tasks.append(response.task)
            isLoading = false
            return response.task
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    // MARK: - Update

    /// Update an existing event.
    func updateEvent(_ eventId: String, request: UpdateEventRequest) async throws -> Event {
        isLoading = true
        error = nil

        do {
            let response: EventResponse = try await apiClient.put("/calendar/events/\(eventId)", body: request)

            if let index = events.firstIndex(where: { $0.id == eventId }) {
                events[index] = response.event
            }

            isLoading = false
            return response.event
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Update an existing task.
    func updateTask(_ taskId: String, request: UpdateTaskRequest) async throws -> Task {
        isLoading = true
        error = nil

        do {
            let response: TaskResponse = try await apiClient.put("/calendar/tasks/\(taskId)", body: request)

            if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[index] = response.task
            }

            isLoading = false
            return response.task
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Toggle task completion.
    func toggleTaskCompletion(_ taskId: String) async throws -> Task {
        guard let task = tasks.first(where: { $0.id == taskId }) else {
            throw CalendarError.taskNotFound
        }

        let request = UpdateTaskRequest(isCompleted: !task.isCompleted)
        return try await updateTask(taskId, request: request)
    }

    /// Toggle event completion.
    func toggleEventCompletion(_ eventId: String) async throws -> Event {
        guard let event = events.first(where: { $0.id == eventId }) else {
            throw CalendarError.eventNotFound
        }

        let request = UpdateEventRequest(isCompleted: !event.isCompleted)
        return try await updateEvent(eventId, request: request)
    }

    // MARK: - Delete

    /// Delete a manual event.
    func deleteEvent(_ eventId: String) async throws {
        isLoading = true
        error = nil

        do {
            try await apiClient.delete("/calendar/events/\(eventId)")
            events.removeAll { $0.id == eventId }
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Delete a task.
    func deleteTask(_ taskId: String) async throws {
        isLoading = true
        error = nil

        do {
            try await apiClient.delete("/calendar/tasks/\(taskId)")
            tasks.removeAll { $0.id == taskId }
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }

    // MARK: - Helpers

    /// Get events for a specific date.
    func events(for date: Date) -> [Event] {
        let calendar = Calendar.current
        return events.filter { calendar.isDate($0.scheduledDate, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Get tasks for a specific date (or unscheduled).
    func tasks(for date: Date?) -> [Task] {
        if let date = date {
            let calendar = Calendar.current
            return tasks.filter { task in
                guard let scheduled = task.scheduledDate else { return false }
                return calendar.isDate(scheduled, inSameDayAs: date)
            }.sorted { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }
        } else {
            return tasks.filter { $0.scheduledDate == nil }
        }
    }

    /// Get unscheduled tasks.
    var unscheduledTasks: [Task] {
        tasks.filter { $0.scheduledDate == nil && !$0.isCompleted }
    }
}

// MARK: - Calendar Error

enum CalendarError: Error, LocalizedError {
    case eventNotFound
    case taskNotFound

    var errorDescription: String? {
        switch self {
        case .eventNotFound:
            return "Event not found"
        case .taskNotFound:
            return "Task not found"
        }
    }
}

// MARK: - API Models

struct EventsResponse: Decodable {
    let events: [Event]
}

struct TasksResponse: Decodable {
    let tasks: [Task]
}

struct EventResponse: Decodable {
    let event: Event
}

struct TaskResponse: Decodable {
    let task: Task
}

struct CreateEventRequest: Encodable {
    let title: String
    let description: String?
    let scheduledDate: Date
    let startTime: Date
    let endTime: Date
    let location: String?
}

struct CreateTaskRequest: Encodable {
    let title: String
    let description: String?
    let scheduledDate: Date?
    let scheduledTime: Date?
    let estimatedMinutes: Int?
}

struct UpdateEventRequest: Encodable {
    var title: String?
    var description: String?
    var startTime: Date?
    var endTime: Date?
    var location: String?
    var isCompleted: Bool?
}

struct UpdateTaskRequest: Encodable {
    var title: String?
    var description: String?
    var scheduledDate: Date?
    var scheduledTime: Date?
    var estimatedMinutes: Int?
    var isCompleted: Bool?
}
