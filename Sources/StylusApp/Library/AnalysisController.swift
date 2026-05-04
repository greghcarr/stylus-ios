import Foundation

// Drives the bridged AnalysisEngine. Exposes queue depth + an "is anything
// running" flag, and pipes onTrackAnalysed events into LibraryStore so the
// in-memory tracks pick up freshly-computed BPM / key without a rescan.
//
// Not @MainActor-isolated because the C trampolines call into our methods
// directly. JUCE's MessageManager dispatches the engine's lifecycle
// callbacks to the main thread on iOS, so the contract is respected
// without compiler enforcement.
final class AnalysisController: ObservableObject
{
    @Published private(set) var queueDepth:         Int     = 0
    @Published private(set) var isAnalysing:        Bool    = false
    @Published private(set) var currentlyAnalysing: String?

    private weak var library: LibraryStore?
    private var      handle:  StylusAnalysisHandle?

    init(library: LibraryStore)
    {
        self.library = library
        let user = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        handle = Stylus_AnalysisCreate(
            analysisOnQueued,
            analysisOnStarted,
            analysisOnAnalysed,
            user
        )
    }

    deinit
    {
        if let h = handle { Stylus_AnalysisDestroy(h) }
    }

    // Queues every track that doesn't already have BOTH bpm and musical key
    // set. The bridge's cheap-skip in Stylus_AnalysisQueue handles already-
    // analysed tracks too, but doing the filter here keeps the queue depth
    // honest and avoids round-tripping through the C ABI for nothing.
    func enqueueUnanalysed(_ tracks: [Track])
    {
        for t in tracks where t.bpm <= 0 || t.key.isEmpty
        {
            enqueue(t)
        }
    }

    func enqueue(_ track: Track)
    {
        guard let handle = handle else { return }
        track.filePath.withCString
        { pathPtr in
            track.key.withCString
            { keyPtr in
                Stylus_AnalysisQueue(handle, pathPtr, track.bpm, keyPtr)
            }
        }
    }

    func cancelAll()
    {
        guard let handle = handle else { return }
        Stylus_AnalysisCancel(handle)
        queueDepth         = 0
        isAnalysing        = false
        currentlyAnalysing = nil
    }

    fileprivate func handleQueued(_ track: Track)
    {
        queueDepth += 1
        isAnalysing = true
    }

    fileprivate func handleStarted(_ track: Track)
    {
        currentlyAnalysing = track.displayTitle
    }

    fileprivate func handleAnalysed(_ track: Track)
    {
        queueDepth         = max(0, queueDepth - 1)
        isAnalysing        = queueDepth > 0
        currentlyAnalysing = isAnalysing ? currentlyAnalysing : nil
        library?.updateTrack(track)
    }
}

// JUCE's MessageManager dispatches the engine's lifecycle callbacks to the
// main thread, so these C trampolines already run on the main thread.

private func analysisOnQueued(trackPtr: UnsafePointer<StylusTrackC>?,
                              userData: UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let ctrl = Unmanaged<AnalysisController>.fromOpaque(userData).takeUnretainedValue()
    ctrl.handleQueued(Track(c: trackPtr.pointee))
}

private func analysisOnStarted(trackPtr: UnsafePointer<StylusTrackC>?,
                               userData: UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let ctrl = Unmanaged<AnalysisController>.fromOpaque(userData).takeUnretainedValue()
    ctrl.handleStarted(Track(c: trackPtr.pointee))
}

private func analysisOnAnalysed(trackPtr: UnsafePointer<StylusTrackC>?,
                                userData: UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let ctrl = Unmanaged<AnalysisController>.fromOpaque(userData).takeUnretainedValue()
    ctrl.handleAnalysed(Track(c: trackPtr.pointee))
}
