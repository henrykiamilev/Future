import SwiftUI

struct CuratedPageView: View {

    @StateObject var viewModel: CuratedPageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.page == nil {
                    VStack {
                        Spacer()
                        ProgressView().tint(Theme.textTertiary)
                        Spacer()
                    }
                } else {
                    pageContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("CURATED")
                        .font(Theme.sectionHeaderFont)
                        .tracking(2.0)
                        .foregroundColor(Theme.textPrimary)
                }
                if viewModel.isOwnProfile {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showEditor = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: {
                Task { await viewModel.load() }
            }) {
                CuratedPageEditView(viewModel: viewModel)
            }
            .task {
                await viewModel.load()
            }
        }
    }

    // MARK: - Page Content

    private var pageContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                headerSection
                    .padding(.bottom, Theme.spacingXL)

                // Divider line
                thinDivider

                // Social handles
                if viewModel.page?.instagramHandle != nil || viewModel.page?.snapchatHandle != nil {
                    socialsSection
                        .padding(.vertical, Theme.spacingL)
                    thinDivider
                }

                // Personality images
                if !personalityImages.isEmpty {
                    imageGridSection
                        .padding(.vertical, Theme.spacingL)
                    thinDivider
                }

                // Q&A
                if let page = viewModel.page, !page.qaPairs.isEmpty {
                    qaSection(pairs: page.qaPairs)
                        .padding(.vertical, Theme.spacingL)
                }

                // Empty state for own profile
                if viewModel.isOwnProfile && isPageEmpty {
                    emptyOwnState
                        .padding(.vertical, Theme.spacingXL)
                }
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.top, Theme.spacingL)
            .padding(.bottom, Theme.spacingXXL)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Theme.spacingS) {
            // Profile photo
            CachedImageView(
                url: SupabaseConfig.storageURL(for: viewModel.page?.profilePhotoUrl ?? ""),
                targetSize: CGSize(width: 120, height: 120)
            ) {
                Circle()
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())

            // Display name (large, resume-style)
            if let displayName = viewModel.page?.displayName, !displayName.isEmpty {
                Text(displayName.uppercased())
                    .font(.custom("OpenSauceSans-Bold", size: 22))
                    .tracking(3.0)
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)
            }

            // Username subtitle
            Text("@\(viewModel.page?.username ?? "")")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
        }
    }

    // MARK: - Socials

    private var socialsSection: some View {
        HStack(spacing: Theme.spacingXL) {
            if let ig = viewModel.page?.instagramHandle, !ig.isEmpty {
                socialBadge(icon: "camera.fill", handle: ig)
            }
            if let sc = viewModel.page?.snapchatHandle, !sc.isEmpty {
                socialBadge(icon: "message.fill", handle: sc)
            }
        }
    }

    private func socialBadge(icon: String, handle: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
            Text(handle)
                .font(Theme.captionFont)
                .foregroundColor(Theme.textPrimary)
        }
    }

    // MARK: - Image Grid (2×2)

    private var personalityImages: [String] {
        viewModel.page?.images ?? []
    }

    private var imageGridSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Text("PERSONALITY")
                .font(Theme.sectionHeaderFont)
                .foregroundColor(Theme.textTertiary)
                .tracking(1.5)
                .padding(.bottom, Theme.spacingXS)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Theme.spacingS),
                GridItem(.flexible(), spacing: Theme.spacingS)
            ], spacing: Theme.spacingS) {
                ForEach(Array(personalityImages.enumerated()), id: \.offset) { _, url in
                    CachedImageView(
                        url: SupabaseConfig.storageURL(for: url),
                        targetSize: CGSize(width: 300, height: 300)
                    ) {
                        Rectangle().fill(Theme.separator)
                    }
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
                }
            }
        }
    }

    // MARK: - Q&A Section

    private func qaSection(pairs: [(prompt: String, answer: String)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 6) {
                    Text(pair.prompt)
                        .font(.custom("OpenSauceSans-SemiBold", size: 13))
                        .foregroundColor(Theme.textPrimary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text(pair.answer)
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Empty State (own profile)

    private var isPageEmpty: Bool {
        guard let p = viewModel.page else { return true }
        return p.images.isEmpty && p.qaPairs.isEmpty
    }

    private var emptyOwnState: some View {
        VStack(spacing: Theme.spacingM) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.textTertiary)

            Text("Your curated page is empty")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)

            Text("Add photos and answer questions\nto let people know who you are.")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showEditor = true
            } label: {
                Text("Set Up")
                    .font(Theme.headlineFont)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.spacingL)
                    .padding(.vertical, Theme.spacingS)
                    .background(Theme.accent)
                    .cornerRadius(Theme.radiusM)
            }
            .padding(.top, Theme.spacingS)
        }
    }

    // MARK: - Shared

    private var thinDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.5)
    }
}
