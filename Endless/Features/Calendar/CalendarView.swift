import SwiftUI

/// Main calendar view - the home screen of the app.
/// Clean weekly calendar with events and tasks.
struct CalendarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var calendarService = CalendarService.shared
    @StateObject private var aiService = AIService.shared

    @State private var selectedDate: Date = Date()
    @State private var selectedEvent: Event?
    @State private var selectedTask: Task?
    @State private var showAddSheet: Bool = false
    @State private var showSettings: Bool = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            // Header with date and actions
            headerSection

            // Week strip
            WeekStripView(
                selectedDate: $selectedDate,
                onDateSelected: { date in
                    selectedDate = date
                }
            )

            // Day content
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    // Events for selected day
                    eventsSection

                    // Tasks for selected day
                    tasksSection

                    // Unscheduled tasks
                    if !calendarService.unscheduledTasks.isEmpty {
                        unscheduledSection
                    }

                    Spacer(minLength: Theme.Spacing.xxxl)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .background(Theme.Colors.background(for: colorScheme))
        .task {
            await calendarService.fetchWeek(containing: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            // Fetch new week if needed
            Task {
                await calendarService.fetchWeek(containing: newDate)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemSheet(selectedDate: selectedDate)
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
        }
        .sheet(isPresented: $showSettings) {
            SettingsPlaceholderView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(formattedMonth)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                Text(formattedYear)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
            }

            Spacer()

            // Token indicator
            if aiService.canGenerate {
                tokenBadge
            }

            // Settings button
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
            }
            .padding(.leading, Theme.Spacing.sm)

            // Add button
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.FallbackColors.accent)
            }
            .padding(.leading, Theme.Spacing.sm)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var tokenBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))

            Text("\(aiService.remainingTokens)")
                .font(Theme.Typography.caption1)
        }
        .foregroundColor(Theme.FallbackColors.accent)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.FallbackColors.accentSubtle)
        .cornerRadius(Theme.Radius.sm)
    }

    // MARK: - Events Section

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader(title: "Events", count: dayEvents.count)

            if dayEvents.isEmpty {
                emptyStateCard(message: "No events scheduled")
            } else {
                ForEach(dayEvents) { event in
                    EventCard(event: event) {
                        selectedEvent = event
                    } onToggle: {
                        toggleEvent(event)
                    }
                }
            }
        }
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader(title: "Tasks", count: dayTasks.count)

            if dayTasks.isEmpty {
                emptyStateCard(message: "No tasks for today")
            } else {
                ForEach(dayTasks) { task in
                    TaskCard(task: task) {
                        selectedTask = task
                    } onToggle: {
                        toggleTask(task)
                    }
                }
            }
        }
    }

    // MARK: - Unscheduled Section

    private var unscheduledSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader(title: "Unscheduled", count: calendarService.unscheduledTasks.count)

            ForEach(calendarService.unscheduledTasks) { task in
                TaskCard(task: task, isCompact: true) {
                    selectedTask = task
                } onToggle: {
                    toggleTask(task)
                }
            }
        }
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

            if count > 0 {
                Text("\(count)")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            }

            Spacer()
        }
    }

    private func emptyStateCard(message: String) -> some View {
        Text(message)
            .font(Theme.Typography.body)
            .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundSecondary(for: colorScheme))
            .cornerRadius(Theme.Radius.md)
    }

    // MARK: - Data

    private var dayEvents: [Event] {
        calendarService.events(for: selectedDate)
    }

    private var dayTasks: [Task] {
        calendarService.tasks(for: selectedDate)
    }

    private var formattedMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: selectedDate)
    }

    private var formattedYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: selectedDate)
    }

    // MARK: - Actions

    private func toggleEvent(_ event: Event) {
        Task {
            do {
                _ = try await calendarService.toggleEventCompletion(event.id)
            } catch {
                print("[CalendarView] Failed to toggle event: \(error)")
            }
        }
    }

    private func toggleTask(_ task: Task) {
        Task {
            do {
                _ = try await calendarService.toggleTaskCompletion(task.id)
            } catch {
                print("[CalendarView] Failed to toggle task: \(error)")
            }
        }
    }
}

// MARK: - Settings Placeholder

struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            VStack {
                Text("Settings")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                Text("Coming in Section 8")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background(for: colorScheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Calendar - Light") {
    CalendarView()
        .environmentObject(AppState())
        .preferredColorScheme(.light)
}

#Preview("Calendar - Dark") {
    CalendarView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
