import SwiftUI

/// Card displaying a task with optional time and completion toggle.
struct TaskCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let task: Task
    var isCompact: Bool = false
    var onTap: () -> Void
    var onToggle: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                // Checkbox
                Button {
                    onToggle()
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: isCompact ? 20 : 24))
                        .foregroundColor(task.isCompleted
                            ? Theme.FallbackColors.accent
                            : Theme.Colors.textTertiary(for: colorScheme))
                }
                .buttonStyle(.plain)

                // Content
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(task.title)
                        .font(isCompact ? Theme.Typography.subheadline : Theme.Typography.headline)
                        .foregroundColor(task.isCompleted
                            ? Theme.Colors.textTertiary(for: colorScheme)
                            : Theme.Colors.textPrimary(for: colorScheme))
                        .strikethrough(task.isCompleted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: Theme.Spacing.sm) {
                        // Time if scheduled
                        if let time = task.scheduledTime {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                Text(formattedTime(time))
                                    .font(Theme.Typography.caption1)
                            }
                            .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                        }

                        // Duration if available
                        if let minutes = task.estimatedMinutes {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.system(size: 10))
                                Text(formattedDuration(minutes))
                                    .font(Theme.Typography.caption1)
                            }
                            .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                        }

                        // AI badge if generated
                        if task.source == .aiGenerated && !isCompact {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("AI")
                                    .font(Theme.Typography.caption2)
                            }
                            .foregroundColor(Theme.FallbackColors.accent.opacity(0.8))
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            }
            .padding(isCompact ? Theme.Spacing.sm : Theme.Spacing.md)
            .background(Theme.Colors.backgroundSecondary(for: colorScheme))
            .cornerRadius(Theme.Radius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatting

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
                return "\(hours)h \(mins)m"
            }
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - Preview

#Preview("Task Card") {
    VStack(spacing: Theme.Spacing.md) {
        TaskCard(
            task: Task(
                userId: "user1",
                title: "Review meeting notes",
                scheduledDate: Date(),
                scheduledTime: Date(),
                estimatedMinutes: 30,
                source: .manual
            ),
            onTap: {},
            onToggle: {}
        )

        TaskCard(
            task: Task(
                userId: "user1",
                title: "Complete GMAT practice questions",
                scheduledDate: Date(),
                estimatedMinutes: 90,
                source: .aiGenerated,
                purpose: "Improve quantitative score"
            ),
            onTap: {},
            onToggle: {}
        )

        TaskCard(
            task: Task(
                userId: "user1",
                title: "Unscheduled task",
                source: .manual
            ),
            isCompact: true,
            onTap: {},
            onToggle: {}
        )
    }
    .padding()
    .background(Color(.systemBackground))
}
