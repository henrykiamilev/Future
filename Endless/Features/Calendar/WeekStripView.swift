import SwiftUI

/// Horizontal week strip for date selection.
/// Shows 7 days with the selected date highlighted.
struct WeekStripView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedDate: Date
    var onDateSelected: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            // Week navigation
            HStack {
                Button {
                    navigateWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                        .frame(width: 32, height: 32)
                }

                Spacer()

                // Today button
                if !calendar.isDateInToday(selectedDate) {
                    Button {
                        withAnimation(Theme.Animation.quick) {
                            selectedDate = Date()
                            onDateSelected(Date())
                        }
                    } label: {
                        Text("Today")
                            .font(Theme.Typography.caption1)
                            .foregroundColor(Theme.FallbackColors.accent)
                    }
                }

                Spacer()

                Button {
                    navigateWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xs)

            // Day cells
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { date in
                    DayCell(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(date)
                    ) {
                        withAnimation(Theme.Animation.quick) {
                            selectedDate = date
                            onDateSelected(date)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)

            Divider()
                .background(Theme.Colors.textTertiary(for: colorScheme).opacity(0.3))
                .padding(.top, Theme.Spacing.sm)
        }
    }

    // MARK: - Week Days

    private var weekDays: [Date] {
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    // MARK: - Navigation

    private func navigateWeek(by weeks: Int) {
        guard let newDate = calendar.date(byAdding: .weekOfYear, value: weeks, to: selectedDate) else { return }
        withAnimation(Theme.Animation.quick) {
            selectedDate = newDate
            onDateSelected(newDate)
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    @Environment(\.colorScheme) private var colorScheme

    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                // Day name
                Text(dayName)
                    .font(Theme.Typography.caption2)
                    .foregroundColor(isSelected
                        ? Theme.FallbackColors.accent
                        : Theme.Colors.textTertiary(for: colorScheme))

                // Day number
                Text(dayNumber)
                    .font(Theme.Typography.headline)
                    .foregroundColor(isSelected
                        ? .white
                        : Theme.Colors.textPrimary(for: colorScheme))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(isSelected
                                ? Theme.FallbackColors.accent
                                : Color.clear)
                    )
                    .overlay(
                        Circle()
                            .stroke(isToday && !isSelected
                                ? Theme.FallbackColors.accent
                                : Color.clear, lineWidth: 1.5)
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Week Strip") {
    VStack {
        WeekStripView(
            selectedDate: .constant(Date()),
            onDateSelected: { _ in }
        )

        Spacer()
    }
    .background(Color(.systemBackground))
}
