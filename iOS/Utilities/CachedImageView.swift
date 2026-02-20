import SwiftUI
import ImageIO

// MARK: - Image Cache

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func clearAll() {
        cache.removeAllObjects()
    }
}

// MARK: - Downsampling

private func downsample(data: Data, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
    let maxPixelSize = max(pointSize.width, pointSize.height) * scale
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}

// MARK: - CachedImageView

struct CachedImageView<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else if failed {
                placeholder()
                    .overlay {
                        Button {
                            retryLoad()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .medium))
                                #if DEBUG
                                Text("Tap to retry")
                                    .font(.caption2)
                                #endif
                            }
                            .foregroundColor(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
            } else {
                placeholder()
            }
        }
        .onAppear { loadIfNeeded() }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: url) { _, _ in
            image = nil
            failed = false
            loadTask?.cancel()
            loadIfNeeded()
        }
    }

    private func retryLoad() {
        failed = false
        image = nil
        loadTask?.cancel()
        loadIfNeeded()
    }

    private func loadIfNeeded() {
        guard let url, image == nil, !failed else { return }

        let key = url.absoluteString
        if let cached = ImageCache.shared.image(for: key) {
            image = cached
            return
        }

        loadTask = Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }

                // Validate HTTP status — URLSession.data doesn't throw on 4xx/5xx
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    #if DEBUG
                    print("[CachedImageView] HTTP \(httpResponse.statusCode) for \(url.absoluteString.prefix(120))")
                    #endif
                    await MainActor.run { failed = true }
                    return
                }

                // Guard against empty responses
                guard !data.isEmpty else {
                    #if DEBUG
                    print("[CachedImageView] Empty data for \(url.absoluteString.prefix(120))")
                    #endif
                    await MainActor.run { failed = true }
                    return
                }

                let scale = UIScreen.main.scale
                let size = targetSize
                let decoded: UIImage? = await Task.detached(priority: .utility) {
                    downsample(data: data, to: size, scale: scale)
                }.value

                guard !Task.isCancelled else { return }

                if let decoded {
                    ImageCache.shared.setImage(decoded, for: key)
                    await MainActor.run { image = decoded }
                } else {
                    #if DEBUG
                    print("[CachedImageView] Decode failed for \(url.absoluteString.prefix(120)) (\(data.count) bytes)")
                    #endif
                    await MainActor.run { failed = true }
                }
            } catch {
                guard !Task.isCancelled else { return }
                #if DEBUG
                print("[CachedImageView] Failed: \(error.localizedDescription) — \(url.absoluteString.prefix(120))")
                #endif
                await MainActor.run { failed = true }
            }
        }
    }
}
