import SwiftUI
import UIKit

/// Two-tier image cache: NSCache for instant in-memory hits, URLCache (disk-backed)
/// for survival across app launches. URLCache is wired into a dedicated URLSession
/// so cached responses come back without a network round-trip.
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let memory = NSCache<NSString, UIImage>()
    let session: URLSession

    init() {
        memory.countLimit = 500
        let disk = URLCache(
            memoryCapacity:  32 * 1024 * 1024,   // 32 MB RAM (for the URL layer)
            diskCapacity:   256 * 1024 * 1024,   // 256 MB on disk
            diskPath:       "RemoteImageCache"
        )
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = disk
        // Use cache, but revalidate with the server (If-None-Match / ETag).
        // Supabase Storage returns ETags, so unchanged images get a tiny 304 and
        // updated images get fresh bytes.
        cfg.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: cfg)
    }

    func image(for url: URL) -> UIImage? { memory.object(forKey: url.absoluteString as NSString) }
    func set(_ image: UIImage, for url: URL) { memory.setObject(image, forKey: url.absoluteString as NSString) }
}

struct RemoteImage: View {
    let urlString: String?
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var failed = false

    init(urlString: String?, contentMode: ContentMode = .fit) {
        self.urlString = urlString
        self.contentMode = contentMode
        // Synchronous cache check on init so cache hits render with no flicker.
        if let s = urlString, let url = URL(string: s),
           let cached = RemoteImageCache.shared.image(for: url) {
            _image = State(initialValue: cached)
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed || urlString == nil {
                Rectangle().fill(Color.cgBorder.opacity(0.3))
            } else {
                Rectangle().fill(Color.cgBorder.opacity(0.15))
                    .overlay(ProgressView().scaleEffect(0.7))
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        guard let s = urlString, let url = URL(string: s) else { failed = true; return }
        if let cached = RemoteImageCache.shared.image(for: url) {
            if image == nil { image = cached }
            return
        }
        do {
            let req = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy)
            let (data, _) = try await RemoteImageCache.shared.session.data(for: req)
            if let ui = UIImage(data: data) {
                RemoteImageCache.shared.set(ui, for: url)
                image = ui
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}
