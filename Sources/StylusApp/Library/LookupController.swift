import Foundation

// Drives the bridged AppleMusicLookup engine. Two flavours:
//   - enqueueAllArtOnly: writes the .styl-art.jpg sidecar; doesn't touch
//     .styl metadata. Use when you just want missing artwork filled in.
//   - enqueue: full metadata + artwork lookup. Fills missing fields on
//     the .styl sidecar (or overwrites existing ones if overwrite=true).
//
// Not @MainActor-isolated for the same reason AnalysisController isn't:
// JUCE's MessageManager already dispatches the engine's lifecycle
// callbacks to the main thread.
final class LookupController: ObservableObject
{
    @Published private(set) var queueDepth:  Int     = 0
    @Published private(set) var inProgress:  Bool    = false
    @Published private(set) var lastStatus:  String?
    @Published private(set) var isSuspended: Bool    = false

    private weak var library: LibraryStore?
    private var      handle:  StylusLookupHandle?

    init(library: LibraryStore)
    {
        self.library = library
        let user = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        handle = Stylus_LookupCreate(
            lookupOnQueued,
            lookupOnStarted,
            lookupOnCompleted,
            lookupOnSuspended,
            user
        )
    }

    deinit
    {
        if let h = handle { Stylus_LookupDestroy(h) }
    }

    // MARK: - Public surface

    // Queue every track that doesn't already have a sidecar artwork file.
    // (We don't pre-check by sniffing the sidecar; the engine handles
    // existing-art short-circuiting itself, but tracks with no artist /
    // album guess are skipped here so we don't waste a network round-trip.)
    func enqueueAllArtOnly(_ tracks: [Track])
    {
        guard let handle = handle else { return }
        for t in tracks
        {
            guard !t.artist.isEmpty || !t.album.isEmpty else { continue }
            t.filePath.withCString
            { p in
                t.artist.withCString
                { a in
                    t.album.withCString
                    { al in
                        Stylus_LookupQueueArtOnly(handle, p, a, al)
                    }
                }
            }
        }
    }

    // Full metadata + artwork lookup for one track.
    func enqueue(_ track: Track, overwrite: Bool)
    {
        guard let handle = handle else { return }
        track.filePath.withCString
        { p in
            track.artist.withCString
            { a in
                track.album.withCString
                { al in
                    track.title.withCString
                    { t in
                        Stylus_LookupQueue(handle, p, a, al, t, overwrite ? 1 : 0)
                    }
                }
            }
        }
    }

    func cancelAll()
    {
        guard let handle = handle else { return }
        Stylus_LookupCancel(handle)
        queueDepth = 0
        inProgress = false
    }

    // MARK: - Bridge callbacks (main thread via JUCE)

    fileprivate func handleQueued(_ track: Track)
    {
        queueDepth += 1
        inProgress = true
    }

    fileprivate func handleStarted(_ track: Track)
    {
        // No-op for now.
    }

    fileprivate func handleCompleted(_ track: Track, status: String, isBatch: Bool)
    {
        queueDepth = max(0, queueDepth - 1)
        inProgress = queueDepth > 0
        lastStatus = status

        // The desktop's lookup engine writes:
        //   - the .styl sidecar (full lookup only) - new metadata fields
        //   - the .styl-art.jpg sidecar (both modes) - downloaded cover
        // Drop the artwork cache entry for this path so the next decode
        // pass picks up the fresh sidecar.
        ArtworkCache.shared.invalidate(for: track.filePath)

        // Refresh the in-memory library entry so any newly-filled artist /
        // album / year / genre / trackNumber lights up across the UI
        // without a rescan.
        library?.updateTrack(track)
    }

    fileprivate func handleSuspended()
    {
        isSuspended = true
        inProgress  = false
    }
}

private func lookupOnQueued(trackPtr: UnsafePointer<StylusTrackC>?,
                            userData: UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let ctrl = Unmanaged<LookupController>.fromOpaque(userData).takeUnretainedValue()
    ctrl.handleQueued(Track(c: trackPtr.pointee))
}

private func lookupOnStarted(trackPtr: UnsafePointer<StylusTrackC>?,
                             userData: UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let ctrl = Unmanaged<LookupController>.fromOpaque(userData).takeUnretainedValue()
    ctrl.handleStarted(Track(c: trackPtr.pointee))
}

private func lookupOnCompleted(trackPtr: UnsafePointer<StylusTrackC>?,
                               status:   UnsafePointer<CChar>?,
                               isBatch:  Int32,
                               userData: UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let ctrl       = Unmanaged<LookupController>.fromOpaque(userData).takeUnretainedValue()
    let statusStr  = status.map { String(cString: $0) } ?? ""
    ctrl.handleCompleted(Track(c: trackPtr.pointee),
                         status: statusStr,
                         isBatch: isBatch != 0)
}

private func lookupOnSuspended(userData: UnsafeMutableRawPointer?)
{
    guard let userData = userData else { return }
    let ctrl = Unmanaged<LookupController>.fromOpaque(userData).takeUnretainedValue()
    ctrl.handleSuspended()
}
