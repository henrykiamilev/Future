import SwiftUI
import ImageIO

// MARK: - Image Cache

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()

    /// Dedicated URLSession with disk caching for images.
    /// Images use immutable UUID paths, so `.returnCacheDataElseLoad` is safe.
    let session: URLSession

    private let diskCache: URLCache

    // Auth — set once at app startup via configure(tokenProvider:anonKey:)
    private var tokenProvider: (() -> String?)?
    private var anonKey: String?

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB memory

        // 20 MB memory + 200 MB disk — separate from APIClient's URLCache
        diskCache = URLCache(
            memoryCapacity: 20_000_000,
            diskCapacity: 200_000_000,
            directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first?.appendingPathComponent("ImageCache")
        )

        let config = URLSessionConfiguration.default
        config.urlCache = diskCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    /// Call once at app startup to enable authenticated image requests.
    func configure(tokenProvider: @escaping () -> String?, anonKey: String) {
        self.tokenProvider = tokenProvider
        self.anonKey = anonKey
    }

    func image(for key: String) -> UIImage? {
        memoryCache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Builds a URLRequest with auth headers for Supabase private storage.
    /// Falls back to a plain request if auth is not configured (e.g. external URLs).
    func authenticatedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        if let anonKey {
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
        }
        if let token = tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Checks whether the disk cache has a stored response for the given URL.
    func hasDiskCache(for url: URL) -> Bool {
        let request = authenticatedRequest(for: url)
        return diskCache.cachedResponse(for: request) != nil
    }

    /// Clears in-memory decoded image cache only.
    func clearAll() {
        memoryCache.removeAllObjects()
    }

    /// Clears both in-memory and on-disk caches. Called on sign-out.
    func clearDiskCache() {
        memoryCache.removeAllObjects()
        diskCache.removeAllCachedResponses()
    }
}

// MARK: - Downsampling

nonisolated private func downsample(data: Data, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
    let maxPixelSize = max(1, max(pointSize.width, pointSize.height) * scale)
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
                    .aspectRatio(contentMode: .fill)
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
            #if DEBUG
            print("[ImageCache] MEM-HIT \(url.lastPathComponent)")
            #endif
            image = cached
            return
        }

        loadTask = Task {
            do {
                #if DEBUG
                let diskHit = ImageCache.shared.hasDiskCache(for: url)
                print("[ImageCache] \(diskHit ? "DISK-HIT" : "MISS") \(url.lastPathComponent)")
                #endif

                let request = ImageCache.shared.authenticatedRequest(for: url)
                var (data, response) = try await ImageCache.shared.session.data(for: request)
                guard !Task.isCancelled else { return }

                // 401 retry: wait briefly for token refresh (triggered elsewhere), then retry
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 401 {
                    #if DEBUG
                    print("[ImageCache] 401 — waiting for token refresh and retrying \(url.lastPathComponent)")
                    #endif
                    // Brief delay to allow concurrent token refresh to complete
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    guard !Task.isCancelled else { return }
                    // Rebuild request with (hopefully) refreshed token, bypass cache
                    var retryRequest = ImageCache.shared.authenticatedRequest(for: url)
                    retryRequest.cachePolicy = .reloadIgnoringLocalCacheData
                    (data, response) = try await ImageCache.shared.session.data(for: retryRequest)
                    guard !Task.isCancelled else { return }
                }

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

                // Use trait collection scale from main actor; fall back to 3.0 (modern iPhones)
                let scale: CGFloat = await MainActor.run {
                    UITraitCollection.current.displayScale > 0 ? UITraitCollection.current.displayScale : 3.0
                }
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
