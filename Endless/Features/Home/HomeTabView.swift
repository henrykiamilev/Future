import SwiftUI

/// Main home container with tab navigation between Calendar and Journal.
/// Clean, minimal tab bar design per PRD.
struct HomeTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab: HomeTab = .calendar

    var body: some View {
        VStack(spacing: 0) {
            // Tab content
            TabView(selection: $selectedTab) {
                CalendarView()
                    .tag(HomeTab.calendar)

                JournalView()
                    .tag(HomeTab.journal)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom tab bar
            customTabBar
        }
    }

    // MARK: - Custom Tab Bar

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabButton(tab: .calendar, icon: "calendar", label: "Calendar")
            tabButton(tab: .journal, icon: "book.closed", label: "Journal")
        }
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
        .background(
            Theme.Colors.background(for: colorScheme)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -2)
        )
    }

    private func tabButton(tab: HomeTab, icon: String, label: String) -> some View {
        Button {
            withAnimation(Theme.Animation.quick) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == tab ? "\(icon).fill" : icon)
                    .font(.system(size: 22))
                    .foregroundColor(selectedTab == tab
                        ? Theme.FallbackColors.accent
                        : Theme.Colors.textTertiary(for: colorScheme))

                Text(label)
                    .font(Theme.Typography.caption2)
                    .foregroundColor(selectedTab == tab
                        ? Theme.FallbackColors.accent
                        : Theme.Colors.textTertiary(for: colorScheme))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home Tab

enum HomeTab {
    case calendar
    case journal
}

// MARK: - Preview

#Preview("Home Tabs - Light") {
    HomeTabView()
        .environmentObject(AppState())
        .preferredColorScheme(.light)
}

#Preview("Home Tabs - Dark") {
    HomeTabView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
