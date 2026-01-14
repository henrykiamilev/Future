import SwiftUI

/// Card displaying an event with time, title, and completion toggle.
struct EventCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let event: Event
    var onTap: () -> Void
    var onToggle: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                // Time column
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedStartTime)
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))

                    Text(formattedEndTime)
                        .font(Theme.Typography.caption2)
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                }
                .frame(width: 50, alignment: .leading)

                // Accent bar
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 3)
                    .cornerRadius(1.5)

                // Content
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(event.title)
                        .font(Theme.Typography.headline)
                        .foregroundColor(event.isCompleted
                            ? Theme.Colors.textTertiary(for: colorScheme)
                            : Theme.Colors.textPrimary(for: colorScheme))
                        .strikethrough(event.isCompleted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 10))
                            Text(location)
                                .font(Theme.Typography.caption1)
                        }
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                    }

                    // AI badge if generated
                    if event.source == .aiGenerated {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("AI Generated")
                                .font(Theme.Typography.caption2)
                        }
                        .foregroundColor(Theme.FallbackColors.accent.opacity(0.8))
                    }
                }

                Spacer()

                // Completion toggle
                Button {
                    onToggle()
                } label: {
                    Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(event.isCompleted
                            ? Theme.FallbackColors.accent
                            : Theme.Colors.textTertiary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundSecondary(for: colorScheme))
            .cornerRadius(Theme.Radius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatting

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

    private var accentColor: Color {
        if event.isCompleted {
            return Theme.Colors.textTertiary(for: colorScheme)
        }
        return event.source == .aiGenerated
            ? Theme.FallbackColors.accent
            : Theme.Colors.textSecondary(for: colorScheme)
    }
}

// MARK: - Preview

#Preview("Event Card") {
    VStack(spacing: Theme.Spacing.md) {
        EventCard(
            event: Event(
                userId: "user1",
                title: "Team Meeting",
                scheduledDate: Date(),
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                location: "Conference Room A",
                source: .manual
            ),
            onTap: {},
            onToggle: {}
        )

        EventCard(
            event: Event(
                userId: "user1",
                title: "Study Session - Advanced Economics",
                scheduledDate: Date(),
                startTime: Date(),
                endTime: Date().addingTimeInterval(7200),
                source: .aiGenerated,
                purpose: "Build foundation for MBA prep"
            ),
            onTap: {},
            onToggle: {}
        )
    }
    .padding()
    .background(Color(.systemBackground))
}
