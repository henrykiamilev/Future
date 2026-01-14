import SwiftUI

/// Sheet for adding a new event or task manually.
struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var calendarService = CalendarService.shared

    let selectedDate: Date

    @State private var itemType: ItemType = .task
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var location: String = ""
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(3600)
    @State private var hasScheduledTime: Bool = false
    @State private var estimatedMinutes: Int = 30
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Type selector
                    typeSelector

                    // Title
                    titleSection

                    // Type-specific fields
                    if itemType == .event {
                        eventFields
                    } else {
                        taskFields
                    }

                    // Description (shared)
                    descriptionSection
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background(for: colorScheme))
            .navigationTitle(itemType == .event ? "New Event" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addItem()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.isEmpty || isLoading)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            setupInitialTimes()
        }
    }

    // MARK: - Type Selector

    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TYPE")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            HStack(spacing: Theme.Spacing.sm) {
                typeButton(type: .task, title: "Task", icon: "checkmark.circle")
                typeButton(type: .event, title: "Event", icon: "calendar")
            }
        }
    }

    private func typeButton(type: ItemType, title: String, icon: String) -> some View {
        Button {
            withAnimation(Theme.Animation.quick) {
                itemType = type
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(Theme.Typography.headline)
            }
            .foregroundColor(itemType == type
                ? .white
                : Theme.Colors.textPrimary(for: colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(itemType == type
                ? Theme.FallbackColors.accent
                : Theme.Colors.backgroundSecondary(for: colorScheme))
            .cornerRadius(Theme.Radius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TITLE")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            TextField(itemType == .event ? "Event title" : "Task title", text: $title)
                .font(Theme.Typography.body)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
        }
    }

    // MARK: - Event Fields

    private var eventFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Date (read-only for events - they're day-locked)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("DATE")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(Theme.FallbackColors.accent)
                    Text(formattedDate(selectedDate))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                    Spacer()
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)

                Text("Events are created for the selected day")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            }

            // Time
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("TIME")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Start")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                        Spacer()
                        DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }

                    Divider()

                    HStack {
                        Text("End")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                        Spacer()
                        DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
            }

            // Location
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("LOCATION (OPTIONAL)")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

                TextField("Add location", text: $location)
                    .font(Theme.Typography.body)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                    .cornerRadius(Theme.Radius.md)
            }
        }
    }

    // MARK: - Task Fields

    private var taskFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Schedule toggle
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("SCHEDULE")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

                VStack(spacing: Theme.Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Schedule for \(formattedShortDate(selectedDate))")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                            Text("Or leave unscheduled to do anytime")
                                .font(Theme.Typography.caption1)
                                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                        }
                        Spacer()
                        Toggle("", isOn: $hasScheduledTime)
                            .labelsHidden()
                            .tint(Theme.FallbackColors.accent)
                    }

                    if hasScheduledTime {
                        Divider()

                        HStack {
                            Text("Time")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                            Spacer()
                            DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
            }

            // Duration
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("ESTIMATED DURATION")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

                Picker("Duration", selection: $estimatedMinutes) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("1 hour").tag(60)
                    Text("1.5 hours").tag(90)
                    Text("2 hours").tag(120)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("DESCRIPTION (OPTIONAL)")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            TextEditor(text: $description)
                .font(Theme.Typography.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }

    private func formattedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func setupInitialTimes() {
        let calendar = Calendar.current
        let now = Date()

        // Round to next hour
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: selectedDate)
        let currentHour = calendar.component(.hour, from: now)
        components.hour = min(currentHour + 1, 23)

        if let start = calendar.date(from: components) {
            startTime = start
            endTime = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        }
    }

    // MARK: - Actions

    private func addItem() {
        isLoading = true

        Task {
            do {
                if itemType == .event {
                    try await createEvent()
                } else {
                    try await createTask()
                }
                dismiss()
            } catch {
                errorMessage = "Failed to create \(itemType == .event ? "event" : "task")"
                isLoading = false
            }
        }
    }

    private func createEvent() async throws {
        // Build proper times for the selected date
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)

        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)

        guard let eventStart = calendar.date(byAdding: startComponents, to: dayStart),
              let eventEnd = calendar.date(byAdding: endComponents, to: dayStart) else {
            throw CalendarError.eventNotFound
        }

        let request = CreateEventRequest(
            title: title,
            description: description.isEmpty ? nil : description,
            scheduledDate: selectedDate,
            startTime: eventStart,
            endTime: eventEnd,
            location: location.isEmpty ? nil : location
        )

        _ = try await calendarService.createEvent(request)
    }

    private func createTask() async throws {
        let calendar = Calendar.current

        var scheduledDate: Date? = nil
        var scheduledTime: Date? = nil

        if hasScheduledTime {
            scheduledDate = selectedDate

            let dayStart = calendar.startOfDay(for: selectedDate)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            scheduledTime = calendar.date(byAdding: timeComponents, to: dayStart)
        }

        let request = CreateTaskRequest(
            title: title,
            description: description.isEmpty ? nil : description,
            scheduledDate: scheduledDate,
            scheduledTime: scheduledTime,
            estimatedMinutes: estimatedMinutes
        )

        _ = try await calendarService.createTask(request)
    }
}

// MARK: - Item Type

enum ItemType {
    case event
    case task
}

// MARK: - Preview

#Preview("Add Item") {
    AddItemSheet(selectedDate: Date())
}
