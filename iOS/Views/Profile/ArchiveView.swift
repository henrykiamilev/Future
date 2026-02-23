import SwiftUI

struct ArchiveView: View {

    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSignatureFullAlert = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    /// Number of posts currently marked as signature
    private var signatureCount: Int {
        viewModel.archivePosts.filter(\.isSignature).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingArchive && viewModel.archivePosts.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView()
                            .tint(Theme.textTertiary)
                        Spacer()
                    }
                } else if viewModel.archivePosts.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "archivebox")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.bottom, Theme.spacingS)
                        Text("Your archive is empty")
                            .font(Theme.bodyFont)
                            .foregroundColor(Theme.textSecondary)
                        Text("Posts you've created will appear here")
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textTertiary)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 0) {
                        // Signature slot indicator
                        signatureSlotBar

                        ScrollView {
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
            .alert("Signature Full", isPresented: $showSignatureFullAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can pin up to 3 posts to your Signature. Remove one first to add a new one.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Signature Slot Bar

    private var signatureSlotBar: some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: "star.fill")
                .font(.system(size: 12))
                .foregroundColor(Theme.accent)

            Text("Signature")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)

            Text("\(signatureCount)/3")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.separator)
                .cornerRadius(Theme.radiusS)

            Spacer()

            Text("Long-press to manage")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS + 2)
        .background(Theme.surface)
    }

    // MARK: - Archive Tile

    private func archiveTile(_ post: ArchivePost) -> some View {
        GeometryReader { geometry in
            let size = geometry.size.width

            CachedImageView(
                url: SupabaseConfig.storageURL(for: post.imageURL),
                targetSize: CGSize(width: size * 2, height: size * 2)
            ) {
                Rectangle().fill(Theme.separator)
            }
            .frame(width: size, height: size)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if post.isSignature {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !post.isActive {
                    Text("Expired")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.5))
                        .cornerRadius(Theme.radiusS)
                        .padding(4)
                }
            }
            .opacity(post.isActive ? 1.0 : 0.6)
            .contentShape(Rectangle())
            .contextMenu {
                signatureContextMenu(for: post)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func signatureContextMenu(for post: ArchivePost) -> some View {
        if post.isSignature {
            Button(role: .destructive) {
                Task {
                    await viewModel.removeFromSignature(postID: post.id)
                    // Reload archive to reflect change
                    await viewModel.loadArchive()
                }
            } label: {
                Label("Remove from Signature", systemImage: "star.slash")
            }
        } else {
            Button {
                if signatureCount >= 3 {
                    showSignatureFullAlert = true
                } else {
                    Task {
                        await viewModel.addToSignature(postID: post.id)
                        // Reload archive to reflect change
                        await viewModel.loadArchive()
                    }
                }
            } label: {
                Label("Add to Signature", systemImage: "star.fill")
            }
        }
    }
}
