import SwiftUI

/// Detail sheet for viewing and editing an event.
/// Shows description, purpose, location, and allows time adjustments.
struct EventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var calendarService = CalendarService.shared

    let event: Event

    @State private var isEditing: Bool = false
    @State private var editedTitle: String = ""
    @State private var editedDescription: String = ""
    @State private var editedLocation: String = ""
    @State private var editedStartTime: Date = Date()
    @State private var editedEndTime: Date = Date()
    @State private var showDeleteConfirm: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Header info
                    headerSection

                    // Time section
                    timeSection

                    // Location
                    if event.location != nil || isEditing {
                        locationSection
                    }

                    // Description
                    if event.description != nil || isEditing {
                        descriptionSection
                    }

                    // AI Context (if AI generated)
                    if event.source == .aiGenerated {
                        aiContextSection
                    }

                    // Delete button (manual events only)
                    if event.canDelete && !isEditing {
                        deleteSection
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background(for: colorScheme))
            .navigationTitle(isEditing ? "Edit Event" : "Event")
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
                    } else if event.canEditDetails || event.canAdjustTime {
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
            .alert("Delete Event", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteEvent()
                }
            } message: {
                Text("Are you sure you want to delete this event?")
            }
        }
        .onAppear {
            resetEditState()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if isEditing && event.canEditDetails {
                TextField("Event title", text: $editedTitle)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
            } else {
                Text(event.title)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
            }

            // Source badge
            HStack(spacing: Theme.Spacing.xs) {
                if event.source == .aiGenerated {
                    Label("AI Generated", systemImage: "sparkles")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.FallbackColors.accent)
                } else {
                    Label("Manual", systemImage: "hand.draw")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                }

                if event.isCompleted {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.FallbackColors.accent)
                }
            }
        }
    }

    // MARK: - Time

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Time")

            if isEditing {
                VStack(spacing: Theme.Spacing.sm) {
                    DatePicker("Start", selection: $editedStartTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()

                    DatePicker("End", selection: $editedEndTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)

                Text("Events can only be moved within the same day")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDate)
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                        Text("\(formattedStartTime) - \(formattedEndTime)")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                    }

                    Spacer()

                    Text("\(event.durationMinutes) min")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Location")

            if isEditing && event.canEditDetails {
                TextField("Location", text: $editedLocation)
                    .font(Theme.Typography.body)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                    .cornerRadius(Theme.Radius.md)
            } else if let location = event.location, !location.isEmpty {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(Theme.FallbackColors.accent)

                    Text(location)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
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

            if isEditing && event.canEditDetails {
                TextEditor(text: $editedDescription)
                    .font(Theme.Typography.body)
                    .frame(minHeight: 100)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                    .cornerRadius(Theme.Radius.md)
            } else if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                    .cornerRadius(Theme.Radius.md)
            }
        }
    }

    // MARK: - AI Context

    private var aiContextSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Why This Event")

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let purpose = event.purpose {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Purpose")
                            .font(Theme.Typography.caption1)
                            .foregroundColor(Theme.FallbackColors.accent)

                        Text(purpose)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                    }
                }

                if let explanation = event.explanation {
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
                Text("Delete Event")
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

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: event.scheduledDate)
    }

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: event.startTime)
    }

    private var formattedEndTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: event.endTime)
    }

    // MARK: - Actions

    private func resetEditState() {
        editedTitle = event.title
        editedDescription = event.description ?? ""
        editedLocation = event.location ?? ""
        editedStartTime = event.startTime
        editedEndTime = event.endTime
    }

    private func startEditing() {
        resetEditState()
        isEditing = true
    }

    private func saveChanges() {
        Task {
            do {
                var request = UpdateEventRequest()

                if event.canEditDetails {
                    request.title = editedTitle
                    request.description = editedDescription.isEmpty ? nil : editedDescription
                    request.location = editedLocation.isEmpty ? nil : editedLocation
                }

                if event.canAdjustTime {
                    // Ensure times stay within the same day
                    let calendar = Calendar.current
                    let dayStart = calendar.startOfDay(for: event.scheduledDate)

                    let startComponents = calendar.dateComponents([.hour, .minute], from: editedStartTime)
                    let endComponents = calendar.dateComponents([.hour, .minute], from: editedEndTime)

                    if let newStart = calendar.date(byAdding: startComponents, to: dayStart),
                       let newEnd = calendar.date(byAdding: endComponents, to: dayStart) {
                        request.startTime = newStart
                        request.endTime = newEnd
                    }
                }

                _ = try await calendarService.updateEvent(event.id, request: request)
                isEditing = false
                dismiss()
            } catch {
                errorMessage = "Failed to save changes"
            }
        }
    }

    private func deleteEvent() {
        Task {
            do {
                try await calendarService.deleteEvent(event.id)
                dismiss()
            } catch {
                errorMessage = "Failed to delete event"
            }
        }
    }
}

// MARK: - Preview

#Preview("Event Detail") {
    EventDetailSheet(
        event: Event(
            userId: "user1",
            title: "Study Session - Advanced Economics",
            description: "Focus on macroeconomic principles and market analysis",
            scheduledDate: Date(),
            startTime: Date(),
            endTime: Date().addingTimeInterval(7200),
            location: "Library",
            source: .aiGenerated,
            purpose: "Build foundation for MBA prep",
            explanation: "Understanding economics is crucial for business school admissions and will help you stand out in interviews."
        )
    )
}
