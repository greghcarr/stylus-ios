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
// thread on cache miss. Mirrors the desktop's AlbumArtExtractor fallback
// chain (embedded -> .styl-art.jpg sidecar -> folder-level cover.jpg etc.)
// since the desktop's juce::Image-returning function isn't linkable on iOS
// (juce_graphics is not in the iOS build).
func loadArtwork(for path: String) async -> UIImage?
{
    if let cached = await ArtworkCache.shared.cached(for: path) { return cached }

    let img: UIImage? = await Task.detached(priority: .userInitiated)
    {
        // 1. Embedded artwork via AVFoundation (bridge wrapper).
        var size: Int = 0
        if let bytes = path.withCString({ Stylus_ExtractArtwork($0, &size) }),
           size > 0
        {
            let data = Data(bytes: bytes, count: size)
            Stylus_FreeArtworkBytes(bytes)
            if let img = UIImage(data: data) { return img }
        }

        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()

        // 2. Per-track sidecar written by the desktop's Apple Music lookup
        //    task: .<filename>.styl-art.jpg next to the audio file.
        let sidecar = dir.appendingPathComponent("." + url.lastPathComponent + ".styl-art.jpg")
        if let img = UIImage(contentsOfFile: sidecar.path) { return img }

        // 3. Folder-level cover art. APFS is case-insensitive so we don't
        //    need to enumerate case variants.
        let names = ["cover", "folder", "artwork", "album", "front"]
        let exts  = ["jpg", "jpeg", "png"]
        for n in names
        {
            for e in exts
            {
                let candidate = dir.appendingPathComponent("\(n).\(e)")
                if let img = UIImage(contentsOfFile: candidate.path) { return img }
            }
        }

        return nil
    }.value

    if let img = img { await ArtworkCache.shared.store(img, for: path) }
    return img
}
