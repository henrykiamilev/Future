import SwiftUI

struct ArchiveView: View {

    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoadingArchive && viewModel.archivePosts.isEmpty {
                    ProgressView()
                        .tint(Theme.textTertiary)
                        .padding(.top, Theme.spacingXXL)
                } else if viewModel.archivePosts.isEmpty {
                    Text("Your archive is empty")
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, Theme.spacingXXL)
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(viewModel.archivePosts) { post in
                            archiveTile(post)
                                .task {
                                    if post.id == viewModel.archivePosts.last?.id {
                                        await viewModel.loadMoreArchive()
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 1)

                    if viewModel.isLoadingArchive {
                        ProgressView()
                            .tint(Theme.textTertiary)
                            .padding(.vertical, Theme.spacingL)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private func archiveTile(_ post: ArchivePost) -> some View {
        let size = (UIScreen.main.bounds.width - 4) / 3

        return CachedImageView(
            url: URL(string: post.imageURL),
            targetSize: CGSize(width: size, height: size)
        ) {
            Rectangle().fill(Theme.separator)
        }
        .scaledToFill()
        .frame(width: size, height: size)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if post.isSignature {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(4)
            }
        }
        .opacity(post.isActive ? 1.0 : 0.6)
    }
}
