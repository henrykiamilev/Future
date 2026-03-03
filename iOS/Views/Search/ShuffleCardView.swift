import SwiftUI
import Combine

struct ShuffleCardView: View {

    let card: ShuffleCard
    let isTopCard: Bool
    let dragOffset: CGSize

    @State private var cycleIndex: Int = 0
    @State private var showContent = false

    private let cardCornerRadius: CGFloat = 22
    private let imageGap: CGFloat = 2
    private let mosaicRatio: CGFloat = 0.72

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mosaicH = h * mosaicRatio
            let statH = h * (1 - mosaicRatio)

            VStack(spacing: 0) {
                mosaicView(width: w, height: mosaicH)
                statStrip(width: w, height: statH)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .scaleEffect(showContent ? 1.0 : 0.96)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    showContent = true
                }
            }
        }
        .onReceive(cycleTimer) { _ in
            guard isTopCard, dragOffset == .zero else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                cycleIndex += 1
            }
        }
    }

    private var cycleTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()
    }

    // MARK: - Mosaic (Zone A)

    @ViewBuilder
    private func mosaicView(width: CGFloat, height: CGFloat) -> some View {
        let images = card.allImages
        let tagStripH: CGFloat = card.allTags.isEmpty ? 0 : 36
        let contentH = height - tagStripH

        ZStack(alignment: .bottom) {
            if images.count >= 3 {
                // Asymmetric layout: large left + two right
                asymmetricMosaic(images: images, width: width, height: contentH)
            } else if images.count == 2 {
                // Two images side by side
                twoImageLayout(images: images, width: width, height: contentH)
            } else if images.count == 1 {
                // Single image full bleed
                mosaicImage(post: images[0], width: width, height: contentH, parallaxFactor: 0.02)
            } else {
                // No images — profile photo fallback
                profilePhotoFallback(width: width, height: contentH)
            }

            // Tag strip overlay
            if !card.allTags.isEmpty {
                tagStripOverlay
                    .frame(height: tagStripH)
            }
        }
        .clipped()
    }

    private func asymmetricMosaic(images: [PostSummary], width: CGFloat, height: CGFloat) -> some View {
        let leftW = width * 0.58
        let rightW = width - leftW - imageGap
        let rightH = (height - imageGap) / 2

        return HStack(spacing: imageGap) {
            // Image A: Large left panel (signature, static)
            mosaicImage(post: images[0], width: leftW, height: height, parallaxFactor: 0.02)

            // Right column: cycles through remaining images
            VStack(spacing: imageGap) {
                // Slot B
                let bIdx = 1 + (cycleIndex % max(1, images.count - 1))
                mosaicImage(
                    post: images[min(bIdx, images.count - 1)],
                    width: rightW,
                    height: rightH,
                    parallaxFactor: 0.04
                )
                .id("slotB-\(bIdx)")
                .transition(.opacity)

                // Slot C
                if images.count >= 3 {
                    let cIdx = 1 + ((cycleIndex + 1) % max(1, images.count - 1))
                    mosaicImage(
                        post: images[min(cIdx, images.count - 1)],
                        width: rightW,
                        height: rightH,
                        parallaxFactor: 0.06
                    )
                    .id("slotC-\(cIdx)")
                    .transition(.opacity)
                } else {
                    Rectangle()
                        .fill(Color(white: 0.12))
                        .frame(width: rightW, height: rightH)
                }
            }
        }
    }

    private func twoImageLayout(images: [PostSummary], width: CGFloat, height: CGFloat) -> some View {
        let halfW = (width - imageGap) / 2
        return HStack(spacing: imageGap) {
            mosaicImage(post: images[0], width: halfW, height: height, parallaxFactor: 0.02)
            mosaicImage(post: images[1], width: halfW, height: height, parallaxFactor: 0.04)
        }
    }

    private func mosaicImage(post: PostSummary, width: CGFloat, height: CGFloat, parallaxFactor: CGFloat) -> some View {
        CachedImageView(
            url: SupabaseConfig.storageURL(for: post.imageURL),
            targetSize: CGSize(width: width * 2.5, height: height * 2.5)
        ) {
            Rectangle()
                .fill(Theme.separator)
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: width, height: height)
        .offset(
            x: dragOffset.width * parallaxFactor,
            y: dragOffset.height * (parallaxFactor * 0.5)
        )
        .clipped()
    }

    private func profilePhotoFallback(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let photoURL = card.profilePhotoURL {
                CachedImageView(
                    url: SupabaseConfig.storageURL(for: photoURL),
                    targetSize: CGSize(width: width * 2, height: height * 2)
                ) {
                    Rectangle().fill(Theme.separator)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
            } else {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: width, height: height)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 48, weight: .thin))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
        }
    }

    // MARK: - Tag Strip

    private var tagStripOverlay: some View {
        HStack(spacing: 6) {
            ForEach(card.allTags.prefix(4)) { tag in
                Text(tag.label)
                    .font(.custom("OpenSauceSans-Medium", size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial.opacity(0.7))
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.5), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Stat Strip (Zone B)

    private func statStrip(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Identity row
            HStack(alignment: .top, spacing: 12) {
                avatarView(size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.username)
                        .font(.custom("OpenSauceSans-Bold", size: 20))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    if let name = card.displayName, !name.isEmpty {
                        Text(name)
                            .font(.custom("OpenSauceSans-Regular", size: 13))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // "SINCE '24" badge
                Text("SINCE \(card.memberSince)")
                    .font(.custom("OpenSauceSans-SemiBold", size: 10))
                    .tracking(1.0)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.separator)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Bio
            if let bio = card.bio, !bio.isEmpty {
                Text(bio)
                    .font(.custom("OpenSauceSans-Regular", size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }

            Spacer(minLength: 4)

            // Stats row
            HStack(spacing: 0) {
                statItem(value: formatStat(card.postCount), label: "posts")
                Spacer()
                statItem(value: formatStat(card.followerCount), label: "followers")
                Spacer()
                statItem(value: "\(card.activityScore)%", label: "active")
                Spacer()
                statItem(value: formatStat(card.totalLikes), label: "likes")
            }
            .padding(.horizontal, 20)

            // Activity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.separator)
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.91, green: 0.66, blue: 0.49),
                                    Color(red: 0.83, green: 0.37, blue: 0.37)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: showContent
                                ? geo.size.width * CGFloat(card.activityScore) / 100
                                : 0,
                            height: 4
                        )
                        .animation(.easeOut(duration: 0.6).delay(0.3), value: showContent)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .background(Color.white)
    }

    // MARK: - Components

    private func avatarView(size: CGFloat) -> some View {
        Group {
            if let photoURL = card.profilePhotoURL {
                CachedImageView(
                    url: SupabaseConfig.storageURL(for: photoURL),
                    targetSize: CGSize(width: size * 2, height: size * 2)
                ) {
                    Circle()
                        .fill(Theme.separator)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textTertiary)
                        }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Theme.separator)
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("OpenSauceSans-SemiBold", size: 15))
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(.custom("OpenSauceSans-Regular", size: 10))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private func formatStat(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
