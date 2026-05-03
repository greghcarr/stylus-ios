import Foundation

final class LibraryStore: ObservableObject
{
    @Published private(set) var tracks:        [Track] = []
    @Published private(set) var isScanning:    Bool    = false
    @Published private(set) var scannedCount:  Int     = 0
    @Published private(set) var expectedCount: Int     = 0

    private var handle:     StylusLibraryHandle?
    // Holds the in-flight fresh-scan results. When the scan completes we swap
    // this in for `tracks` atomically, so the UI sees the cached library
    // continuously and then jumps to the fresh one in a single update.
    private var scanBuffer: [Track] = []

    // Mirrors the desktop scanner's filter (Constants::supportedExtensions).
    // Used by the pre-count pass to set expectedCount before the scanner
    // itself reports tracks one-by-one.
    private static let audioExtensions: Set<String> = [
        "mp3", "flac", "wav", "aiff", "aif", "m4a", "aac", "alac", "ogg", "opus"
    ]

    deinit
    {
        if let h = handle { Stylus_LibraryDestroy(h) }
    }

    // Caller is expected to have an active security scope on the URL for the
    // duration of the scan and any subsequent playback.
    func scan(folder url: URL)
    {
        scan(folders: [url.path])
    }

    func scan(folders: [String])
    {
        if let h = handle
        {
            Stylus_LibraryDestroy(h)
            handle = nil
        }
        tracks.removeAll()
        scanBuffer.removeAll()
        scannedCount  = 0
        expectedCount = 0
        isScanning    = true

        // Pre-count audio files in parallel so the scanning progress bar can
        // become determinate quickly. The actual scan (which reads metadata)
        // runs orders of magnitude slower than this enumeration pass.
        for path in folders
        {
            let folderURL = URL(fileURLWithPath: path)
            DispatchQueue.global(qos: .userInitiated).async
            { [weak self] in
                let n = LibraryStore.countAudioFiles(at: folderURL)
                DispatchQueue.main.async
                { [weak self] in
                    guard let self = self, self.isScanning else { return }
                    self.expectedCount += n
                }
            }
        }

        let owned: [UnsafeMutablePointer<CChar>?] = folders.map { strdup($0) }
        defer { owned.forEach { if let p = $0 { free(p) } } }
        var ptrs: [UnsafePointer<CChar>?] = owned.map { $0.map { UnsafePointer($0) } }

        ptrs.withUnsafeMutableBufferPointer
        { buf in
            handle = Stylus_LibraryCreate(buf.baseAddress, Int32(folders.count))
        }

        let user = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // Phase 1: instant repopulate from the on-disk cache. Fires
        // libraryStoreOnCachedTrack once per cached track on this thread.
        _ = Stylus_LibraryLoadCache(handle, libraryStoreOnCachedTrack, user)

        // Phase 2: kick off the fresh background scan. Scanned tracks
        // accumulate in scanBuffer; the cached `tracks` stay visible until
        // libraryStoreOnScanDone swaps them in atomically.
        Stylus_LibraryStartScan(handle,
                                libraryStoreOnScannedTrack,
                                libraryStoreOnScanDone,
                                user)
    }

    fileprivate func appendCachedTrack(_ track: Track)
    {
        tracks.append(track)
    }

    fileprivate func appendScannedTrack(_ track: Track)
    {
        scanBuffer.append(track)
        scannedCount += 1
    }

    fileprivate func scanCompleted()
    {
        // Atomic swap: replace the (possibly stale) cached library with the
        // fresh scan results. Single SwiftUI invalidation.
        tracks        = scanBuffer
        scanBuffer    = []
        isScanning    = false
        scannedCount  = 0
        expectedCount = 0
    }

    private static func countAudioFiles(at root: URL) -> Int
    {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root,
                                              includingPropertiesForKeys: nil,
                                              options: [])
        else { return 0 }

        var count = 0
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in enumerator
        {
            // Match the desktop scanner's "skip any path component starting
            // with `.`" rule (this is what hides .styl sidecars and any
            // `.hidden` folders).
            var cur = url.standardizedFileURL
            var hidden = false
            while cur.path != rootPath
            {
                if cur.lastPathComponent.hasPrefix(".") { hidden = true; break }
                cur = cur.deletingLastPathComponent()
            }
            if hidden { continue }

            if audioExtensions.contains(url.pathExtension.lowercased())
            {
                count += 1
            }
        }
        return count
    }
}

// JUCE's MessageManager dispatches the scanner's batch + done callbacks to the
// main thread, so these C callbacks already run on the main thread.

private func libraryStoreOnCachedTrack(trackPtr: UnsafePointer<StylusTrackC>?,
                                       userData:  UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let store = Unmanaged<LibraryStore>.fromOpaque(userData).takeUnretainedValue()
    store.appendCachedTrack(Track(c: trackPtr.pointee))
}

private func libraryStoreOnScannedTrack(trackPtr: UnsafePointer<StylusTrackC>?,
                                        userData:  UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let store = Unmanaged<LibraryStore>.fromOpaque(userData).takeUnretainedValue()
    store.appendScannedTrack(Track(c: trackPtr.pointee))
}

private func libraryStoreOnScanDone(total:    Int32,
                                    userData: UnsafeMutableRawPointer?)
{
    guard let userData = userData else { return }
    let store = Unmanaged<LibraryStore>.fromOpaque(userData).takeUnretainedValue()
    store.scanCompleted()
}
