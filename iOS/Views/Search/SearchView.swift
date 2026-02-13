import SwiftUI

struct SearchView: View {

    @StateObject var viewModel: SearchViewModel
    let onUserTapped: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            resultsList
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("DISCOVER")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(2.0)
                    .foregroundColor(Theme.textPrimary)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Theme.textTertiary)

            TextField("Search users...", text: $viewModel.query)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: viewModel.query) { _, _ in
                    viewModel.onQueryChanged()
                }

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.onQueryChanged()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .cornerRadius(Theme.radiusM)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusM)
                .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, Theme.spacingM)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if viewModel.isSearching {
            Spacer()
            ProgressView()
                .tint(Theme.textTertiary)
            Spacer()
        } else if let error = viewModel.error {
            Spacer()
            VStack(spacing: Theme.spacingS) {
                Text("Search failed")
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                Text(error)
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.spacingXL)
            Spacer()
        } else if viewModel.results.isEmpty && viewModel.hasSearched {
            Spacer()
            VStack(spacing: Theme.spacingS) {
                Text("No users found")
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                Text("Try a different search.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        } else if viewModel.results.isEmpty {
            Spacer()
            VStack(spacing: Theme.spacingS) {
                Image(systemName: "person.2")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundColor(Theme.textTertiary)
                Text("Find people")
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                Text("Search by username to discover new accounts.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.spacingXL)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.results) { user in
                        userRow(user)
                    }
                }
            }
        }
    }

    private func userRow(_ user: UserSummary) -> some View {
        NavigationLink(value: user.id) {
            HStack(spacing: Theme.spacingM) {
                CachedImageView(
                    url: URL(string: user.profilePhotoURL ?? ""),
                    targetSize: CGSize(width: 44, height: 44)
                ) {
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.vertical, Theme.spacingM)
        }
        .buttonStyle(.plain)
    }
}
