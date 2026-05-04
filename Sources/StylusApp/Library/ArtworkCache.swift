import UIKit
import ImageIO

// Two-tier in-memory cache for decoded album art:
//   - thumbnails: 132 px max edge (44 pt @ 3x). Used by every list row,
//     the transport bar, and the Up Next list in the Now Playing sheet.
//   - largeArt:    1200 px max edge. Used by the Now Playing sheet's
//     hero artwork and by MPNowPlayingInfoCenter (lock-screen + AirPlay
//     output).
//
// The previous implementation cached full-resolution UIImages (often
// ~1000 x 1000 JPEGs decoded into ~4 MB each) and bounded only by count
// (200). On a 1000-track library the resident memory could shoot past
// 800 MB and iOS would kill the app, especially when the Up Next list
// fanned out artwork loads on scroll. ImageIO downsampling at decode
// time keeps a thumbnail at ~50 KB and a hero image at ~1 MB.
final class ArtworkCache
{
    static let shared = ArtworkCache()

    static let thumbnailMaxPixelSize: CGFloat = 132
    static let fullArtMaxPixelSize:   CGFloat = 1200

    private let thumbnails = NSCache<NSString, UIImage>()
    private let largeArt   = NSCache<NSString, UIImage>()

    private init()
    {
        thumbnails.countLimit = 300
        largeArt.countLimit   = 8
    }

    func cachedThumbnail(for path: String) -> UIImage?
    {
        thumbnails.object(forKey: path as NSString)
    }

    func cachedFullArtwork(for path: String) -> UIImage?
    {
        largeArt.object(forKey: path as NSString)
    }

    func storeThumbnail(_ image: UIImage, for path: String)
    {
        thumbnails.setObject(image, forKey: path as NSString)
    }

    func storeFullArtwork(_ image: UIImage, for path: String)
    {
        largeArt.setObject(image, forKey: path as NSString)
    }

    // Drops both tiers for the given track. Used after a lookup writes a
    // new sidecar so subsequent loads pick it up.
    func invalidate(for path: String)
    {
        thumbnails.removeObject(forKey: path as NSString)
        largeArt.removeObject(forKey: path as NSString)
    }
}

// Reads raw artwork bytes from disk via the same fallback chain as before:
// embedded artwork via AVFoundation -> .styl-art.jpg sidecar -> folder-
// level cover.{jpg,jpeg,png}. Returns Data (undecoded); caller decides
// what size to decode at.
private func loadArtworkData(for path: String) -> Data?
{
    var size: Int = 0
    if let bytes = path.withCString({ Stylus_ExtractArtwork($0, &size) }),
       size > 0
    {
        let data = Data(bytes: bytes, count: size)
        Stylus_FreeArtworkBytes(bytes)
        return data
    }

    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()

    let sidecar = dir.appendingPathComponent("." + url.lastPathComponent + ".styl-art.jpg")
    if let d = try? Data(contentsOf: sidecar) { return d }

    let names = ["cover", "folder", "artwork", "album", "front"]
    let exts  = ["jpg", "jpeg", "png"]
    for n in names
    {
        for e in exts
        {
            let candidate = dir.appendingPathComponent("\(n).\(e)")
            if let d = try? Data(contentsOf: candidate) { return d }
        }
    }
    return nil
}

// ImageIO-backed downsample: decodes at the smallest size that satisfies
// `maxPixelSize`. kCGImageSourceShouldCacheImmediately forces decode now
// (not on first paint), so we don't pay the cost on the main thread later.
private func decodeImage(data: Data, maxPixelSize: CGFloat) -> UIImage?
{
    guard let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return nil }

    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform:   true,
        kCGImageSourceShouldCacheImmediately:         true,
        kCGImageSourceThumbnailMaxPixelSize:          maxPixelSize,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }

    return UIImage(cgImage: cgImage,
                   scale:   UIScreen.main.scale,
                   orientation: .up)
}

// Async decode + cache for thumbnail-sized art. Used by every list row.
func loadThumbnail(for path: String) async -> UIImage?
{
    if let cached = ArtworkCache.shared.cachedThumbnail(for: path) { return cached }

    let img: UIImage? = await Task.detached(priority: .userInitiated)
    {
        guard let data = loadArtworkData(for: path) else { return nil }
        return decodeImage(data: data, maxPixelSize: ArtworkCache.thumbnailMaxPixelSize)
    }.value

    if let img = img { ArtworkCache.shared.storeThumbnail(img, for: path) }
    return img
}

// Async decode + cache for the larger Now Playing / lock-screen artwork.
func loadFullArtwork(for path: String) async -> UIImage?
{
    if let cached = ArtworkCache.shared.cachedFullArtwork(for: path) { return cached }

    let img: UIImage? = await Task.detached(priority: .userInitiated)
    {
        guard let data = loadArtworkData(for: path) else { return nil }
        return decodeImage(data: data, maxPixelSize: ArtworkCache.fullArtMaxPixelSize)
    }.value

    if let img = img { ArtworkCache.shared.storeFullArtwork(img, for: path) }
    return img
}
