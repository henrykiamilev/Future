import SwiftUI

struct FollowListView: View {

    @StateObject var viewModel: FollowListViewModel
    let onUserTapped: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            segmentedControl
            listContent
        }
        .background(Theme.background)
        .navigationTitle(viewModel.selectedSegment.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(FollowListViewModel.Segment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedSegment = segment
                    }
                } label: {
                    VStack(spacing: Theme.spacingS) {
                        Text(segmentLabel(segment))
                            .font(Theme.headlineFont)
                            .foregroundColor(
                                viewModel.selectedSegment == segment
                                    ? Theme.textPrimary
                                    : Theme.textTertiary
                            )

                        Rectangle()
                            .fill(
                                viewModel.selectedSegment == segment
                                    ? Theme.accent
                                    : Color.clear
                            )
                            .frame(height: 1.5)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.top, Theme.spacingS)
        .background(Theme.background)
    }

    private func segmentLabel(_ segment: FollowListViewModel.Segment) -> String {
        let count = segment == .followers ? viewModel.followers.count : viewModel.following.count
        return "\(segment.rawValue) (\(count))"
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView()
                .tint(Theme.textTertiary)
            Spacer()
        } else if viewModel.currentList.isEmpty {
            Spacer()
            VStack(spacing: Theme.spacingS) {
                Text(viewModel.selectedSegment == .followers
                     ? "No followers yet"
                     : "Not following anyone")
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.currentList) { user in
                        userRow(user)
                    }
                }
            }
        }
    }

    private func userRow(_ user: UserSummary) -> some View {
        Button {
            onUserTapped(user.id)
        } label: {
            HStack(spacing: Theme.spacingM) {
                AsyncImage(url: URL(string: user.profilePhotoURL ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Theme.separator)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textTertiary)
                        }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.textPrimary)

                    if let name = user.displayName, !name.isEmpty {
                        Text(name)
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.vertical, Theme.spacingM)
        }
        .buttonStyle(.plain)
    }
}
