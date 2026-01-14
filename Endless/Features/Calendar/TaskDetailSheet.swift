import SwiftUI

/// Detail sheet for viewing and editing a task.
/// Tasks are fully flexible - can be rescheduled, edited, or deleted.
struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var calendarService = CalendarService.shared

    let task: Task

    @State private var isEditing: Bool = false
    @State private var editedTitle: String = ""
    @State private var editedDescription: String = ""
    @State private var editedDate: Date = Date()
    @State private var editedTime: Date = Date()
    @State private var hasScheduledDate: Bool = false
    @State private var hasScheduledTime: Bool = false
    @State private var editedDuration: Int = 30
    @State private var showDeleteConfirm: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Header info
                    headerSection

                    // Schedule section
                    scheduleSection

                    // Duration
                    durationSection

                    // Description
                    descriptionSection

                    // AI Context (if AI generated)
                    if task.source == .aiGenerated {
                        aiContextSection
                    }

                    // Delete button
                    if !isEditing {
                        deleteSection
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background(for: colorScheme))
            .navigationTitle(isEditing ? "Edit Task" : "Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                            resetEditState()
                        }
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            saveChanges()
                        }
                        .fontWeight(.semibold)
                    } else {
                        Button("Edit") {
                            startEditing()
                        }
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Delete Task", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteTask()
                }
            } message: {
                Text("Are you sure you want to delete this task?")
            }
        }
        .onAppear {
            resetEditState()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if isEditing {
                TextField("Task title", text: $editedTitle)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
            } else {
                Text(task.title)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                    .strikethrough(task.isCompleted)
            }

            // Source badge
            HStack(spacing: Theme.Spacing.xs) {
                if task.source == .aiGenerated {
                    Label("AI Generated", systemImage: "sparkles")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.FallbackColors.accent)
                } else {
                    Label("Manual", systemImage: "hand.draw")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                }

                if task.isCompleted {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.FallbackColors.accent)
                }

                if task.isOverdue {
                    Label("Overdue", systemImage: "exclamationmark.circle")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Color(hex: "E55050"))
                }
            }

            // Flexibility note
            Text("Tasks are flexible and can be rescheduled anytime")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                .padding(.top, Theme.Spacing.xxs)
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Schedule")

            if isEditing {
                VStack(spacing: Theme.Spacing.md) {
                    // Date toggle
                    Toggle("Schedule for a day", isOn: $hasScheduledDate)
                        .tint(Theme.FallbackColors.accent)

                    if hasScheduledDate {
                        DatePicker("Date", selection: $editedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)

                        // Time toggle
                        Toggle("Set specific time", isOn: $hasScheduledTime)
                            .tint(Theme.FallbackColors.accent)

                        if hasScheduledTime {
                            DatePicker("Time", selection: $editedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
            } else {
                if let date = task.scheduledDate {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formattedDate(date))
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                            if let time = task.scheduledTime {
                                Text(formattedTime(time))
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                            } else {
                                Text("No specific time")
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                            }
                        }

                        Spacer()
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                    .cornerRadius(Theme.Radius.md)
                } else {
                    Text("Not scheduled")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                        .cornerRadius(Theme.Radius.md)
                }
            }
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Estimated Duration")

            if isEditing {
                Picker("Duration", selection: $editedDuration) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("1 hour").tag(60)
                    Text("1.5 hours").tag(90)
                    Text("2 hours").tag(120)
                    Text("3 hours").tag(180)
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
            } else {
                HStack {
                    Image(systemName: "timer")
                        .foregroundColor(Theme.FallbackColors.accent)

                    if let minutes = task.estimatedMinutes {
                        Text(formattedDuration(minutes))
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                    } else {
                        Text("Not set")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
            }
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Description")

            if isEditing {
                TextEditor(text: $editedDescription)
                    .font(Theme.Typography.body)
                    .frame(minHeight: 100)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                    .cornerRadius(Theme.Radius.md)
            } else if let description = task.description, !description.isEmpty {
                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                    .cornerRadius(Theme.Radius.md)
            } else {
                Text("No description")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                    .cornerRadius(Theme.Radius.md)
            }
        }
    }

    // MARK: - AI Context

    private var aiContextSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Why This Task")

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let purpose = task.purpose {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Purpose")
                            .font(Theme.Typography.caption1)
                            .foregroundColor(Theme.FallbackColors.accent)

                        Text(purpose)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                    }
                }

                if let explanation = task.explanation {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("How This Helps")
                            .font(Theme.Typography.caption1)
                            .foregroundColor(Theme.FallbackColors.accent)

                        Text(explanation)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.FallbackColors.accentSubtle)
            .cornerRadius(Theme.Radius.md)
        }
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Task")
            }
            .font(Theme.Typography.body)
            .foregroundColor(Color(hex: "E55050"))
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.md)
            .background(Color(hex: "E55050").opacity(0.1))
            .cornerRadius(Theme.Radius.md)
        }
        .padding(.top, Theme.Spacing.lg)
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.caption1)
            .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            .textCase(.uppercase)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func formattedDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins > 0 {
                return "\(hours) hour\(hours > 1 ? "s" : "") \(mins) min"
            }
            return "\(hours) hour\(hours > 1 ? "s" : "")"
        }
        return "\(minutes) minutes"
    }

    // MARK: - Actions

    private func resetEditState() {
        editedTitle = task.title
        editedDescription = task.description ?? ""
        editedDate = task.scheduledDate ?? Date()
        editedTime = task.scheduledTime ?? Date()
        hasScheduledDate = task.scheduledDate != nil
        hasScheduledTime = task.scheduledTime != nil
        editedDuration = task.estimatedMinutes ?? 30
    }

    private func startEditing() {
        resetEditState()
        isEditing = true
    }

    private func saveChanges() {
        Task {
            do {
                let request = UpdateTaskRequest(
                    title: editedTitle,
                    description: editedDescription.isEmpty ? nil : editedDescription,
                    scheduledDate: hasScheduledDate ? editedDate : nil,
                    scheduledTime: hasScheduledDate && hasScheduledTime ? editedTime : nil,
                    estimatedMinutes: editedDuration
                )

                _ = try await calendarService.updateTask(task.id, request: request)
                isEditing = false
                dismiss()
            } catch {
                errorMessage = "Failed to save changes"
            }
        }
    }

    private func deleteTask() {
        Task {
            do {
                try await calendarService.deleteTask(task.id)
                dismiss()
            } catch {
                errorMessage = "Failed to delete task"
            }
        }
    }
}

// MARK: - Preview

#Preview("Task Detail") {
    TaskDetailSheet(
        task: Task(
            userId: "user1",
            title: "Complete GMAT practice questions",
            description: "Focus on quantitative reasoning section",
            scheduledDate: Date(),
            scheduledTime: Date(),
            estimatedMinutes: 90,
            source: .aiGenerated,
            purpose: "Improve quantitative score",
            explanation: "Consistent practice with timed questions will help you develop the speed and accuracy needed for the GMAT."
        )
    )
}
