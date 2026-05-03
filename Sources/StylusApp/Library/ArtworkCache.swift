import UIKit

// In-memory cache of decoded album-art `UIImage`s keyed by track file path.
// Bounded by `NSCache.countLimit` so iOS can evict under memory pressure.
@MainActor
final class ArtworkCache
{
    static let shared = ArtworkCache()

    private let cache = NSCache<NSString, UIImage>()

    private init()
    {
        cache.countLimit = 200
    }

    func cached(for path: String) -> UIImage?
    {
        cache.object(forKey: path as NSString)
    }

    func store(_ image: UIImage, for path: String)
    {
        cache.setObject(image, forKey: path as NSString)
    }
}

// Returns the album art for the given track path, decoding off the main
// thread on cache miss. Returns nil if the file has no embedded artwork.
func loadArtwork(for path: String) async -> UIImage?
{
    if let cached = await ArtworkCache.shared.cached(for: path) { return cached }

    let img: UIImage? = await Task.detached(priority: .userInitiated)
    {
        var size: Int = 0
        guard let bytes = path.withCString({ Stylus_ExtractArtwork($0, &size) }),
              size > 0
        else { return nil }
        let data = Data(bytes: bytes, count: size)
        Stylus_FreeArtworkBytes(bytes)
        return UIImage(data: data)
    }.value

    if let img = img { await ArtworkCache.shared.store(img, for: path) }
    return img
}
