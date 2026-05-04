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

    // Caller is expected to have active security scopes on both URLs for
    // the duration of the scan + subsequent playback.
    //
    // forceFullScan: when false (default), the slow metadata-reading
    // scan is skipped at launch if the cache repopulated successfully
    // AND a quick recursive file count of the folders matches the
    // cached track count -- i.e. nothing has been added or removed.
    // Set true for the user-triggered Rescan menu item so it always
    // re-reads metadata even when no files have changed (catches
    // tags edited externally on the desktop).
    func scan(music: URL?, podcast: URL?, forceFullScan: Bool = false)
    {
        scan(musicPaths:   music.map   { [$0.path] } ?? [],
             podcastPaths: podcast.map { [$0.path] } ?? [],
             forceFullScan: forceFullScan)
    }

    func scan(musicPaths:    [String],
              podcastPaths:  [String],
              forceFullScan: Bool = false)
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
        // runs orders of magnitude slower than this enumeration pass. We
        // count music + podcasts so the bar reflects total expected tracks.
        for path in (musicPaths + podcastPaths)
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

        let musicOwned:   [UnsafeMutablePointer<CChar>?] = musicPaths.map   { strdup($0) }
        let podcastOwned: [UnsafeMutablePointer<CChar>?] = podcastPaths.map { strdup($0) }
        defer
        {
            musicOwned.forEach   { if let p = $0 { free(p) } }
            podcastOwned.forEach { if let p = $0 { free(p) } }
        }
        var musicPtrs:   [UnsafePointer<CChar>?] = musicOwned.map   { $0.map { UnsafePointer($0) } }
        var podcastPtrs: [UnsafePointer<CChar>?] = podcastOwned.map { $0.map { UnsafePointer($0) } }

        musicPtrs.withUnsafeMutableBufferPointer
        { musicBuf in
            podcastPtrs.withUnsafeMutableBufferPointer
            { podcastBuf in
                handle = Stylus_LibraryCreate(
                    musicBuf.baseAddress,   Int32(musicPaths.count),
                    podcastBuf.baseAddress, Int32(podcastPaths.count)
                )
            }
        }

        let user = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // Phase 1: instant repopulate from the on-disk cache. Fires
        // libraryStoreOnCachedTrack once per cached track on this thread.
        _ = Stylus_LibraryLoadCache(handle, libraryStoreOnCachedTrack, user)

        // Phase 1.5: skip the slow metadata scan when the cache had
        // tracks AND a quick FileManager enumeration shows the same
        // count -- i.e. no files added or removed since the last
        // scan. countAudioFiles is orders of magnitude faster than
        // the metadata reads in Phase 2 (~50 ms vs minutes for ~1k
        // tracks), so this lets dev-build launches feel instant.
        // Bypassed when forceFullScan is true (toolbar Rescan) so
        // externally-edited tags still get picked up on demand.
        if !forceFullScan && !tracks.isEmpty
        {
            // Sum-of-counts double-counts files when the podcast
            // root lives inside the music root (the typical "music/
            // Podcasts" layout). Walk all folders into a set keyed
            // by canonical path so each file is counted at most
            // once -- matches the desktop scanner's behaviour, which
            // de-dupes across overlapping roots.
            let folderURLs  = (musicPaths + podcastPaths)
                .map { URL(fileURLWithPath: $0) }
            let actualCount = LibraryStore
                .countUniqueAudioFiles(in: folderURLs)
            if actualCount == tracks.count
            {
                isScanning    = false
                scannedCount  = 0
                expectedCount = 0
                return
            }
        }

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

    // Replaces an existing track in-place by file-path identity. Used by
    // Analysis / Lookup controllers when a freshly-processed track comes
    // back, so BPM / key / metadata in the UI update without a full rescan.
    func updateTrack(_ updated: Track)
    {
        if let idx = tracks.firstIndex(where: { $0.filePath == updated.filePath })
        {
            tracks[idx] = updated
        }
    }

    // Persists the edited Track to its .styl sidecar AND updates the
    // in-memory entry. The bridge's Stylus_StylSave re-loads existing
    // sidecar data first so disk-side fields the user didn't edit
    // (playCount, dateAdded, lufs, etc.) survive.
    @discardableResult
    func save(_ track: Track) -> Bool
    {
        let ok = saveTrackToStyl(track)
        if ok { updateTrack(track) }
        return ok
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

    // Counts audio files across multiple roots, de-duplicated by
    // canonical path so a file that sits under two roots (typical
    // when the podcast folder is a subdirectory of the music
    // folder) is counted once. Used by the launch-time skip-scan
    // check, which compares this against the cache's track count.
    private static func countUniqueAudioFiles(in roots: [URL]) -> Int
    {
        let fm = FileManager.default
        var seen = Set<String>()

        for root in roots
        {
            guard let enumerator = fm.enumerator(
                    at:                         root,
                    includingPropertiesForKeys: nil,
                    options:                    [])
            else { continue }
            let rootPath = root.standardizedFileURL.path

            for case let url as URL in enumerator
            {
                var cur    = url.standardizedFileURL
                var hidden = false
                while cur.path != rootPath
                {
                    if cur.lastPathComponent.hasPrefix(".")
                    { hidden = true; break }
                    cur = cur.deletingLastPathComponent()
                }
                if hidden { continue }

                if audioExtensions.contains(
                    url.pathExtension.lowercased())
                {
                    seen.insert(url.standardizedFileURL.path)
                }
            }
        }
        return seen.count
    }
}

// Free function so the deeply-nested withCString chains needed to fill a
// StylusTrackC don't clutter LibraryStore. Shared by EditInfoView's Save.
func saveTrackToStyl(_ track: Track) -> Bool
{
    return track.filePath.withCString
    { p in
        track.title.withCString
        { ti in
            track.artist.withCString
            { a in
                track.album.withCString
                { al in
                    track.genre.withCString
                    { g in
                        track.year.withCString
                        { y in
                            track.key.withCString
                            { k in
                                var c = StylusTrackC()
                                c.filePath        = p
                                c.title           = ti
                                c.artist          = a
                                c.album           = al
                                c.genre           = g
                                c.year            = y
                                c.musicalKey      = k
                                c.trackNumber     = Int32(track.trackNumber)
                                c.durationSeconds = track.durationSeconds
                                c.bpm             = track.bpm
                                c.lufs            = 0
                                c.isPodcast       = 0
                                c.podcast         = nil
                                c.dateAddedMillis = 0
                                c.playCount       = 0
                                return withUnsafePointer(to: &c)
                                { ptr in
                                    Stylus_StylSave(ptr) != 0
                                }
                            }
                        }
                    }
                }
            }
        }
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
