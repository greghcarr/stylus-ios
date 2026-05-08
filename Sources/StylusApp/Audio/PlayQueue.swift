import Foundation

// Swift-side play queue: ordered list of tracks plus a current index. Mirrors
// the desktop PlayQueue's surface (advance / goBack / jump / setQueue plus
// shuffle + repeat) but isn't bridged - the C++ version is tied to TrackInfo
// and the marshalling overhead would dominate the trivial logic. Keeps shuffle
// state machine identical to the desktop so behaviour is the same on both
// platforms (saved-original-order + on-shuffle-move-current-to-index-0).
final class PlayQueue: ObservableObject
{
    enum RepeatMode: Int
    {
        case off  = 0
        case all  = 1   // wrap-to-start at end of queue (auto-advance only)
        case one  = 2   // replay current track on natural track-end
    }

    @Published private(set) var tracks:       [Track] = []
    @Published private(set) var currentIndex: Int     = 0

    @Published private(set) var isShuffled:   Bool       = false
    @Published         var      repeatMode:   RepeatMode = .off

    // Snapshot of the un-shuffled track order, captured the moment shuffle is
    // turned on. unshuffle() restores this whole list (placing the playing
    // track back at its original index). Append / insert while shuffled also
    // appends to this list so a later un-shuffle still includes those tracks.
    private var originalTracks: [Track] = []

    var currentTrack: Track?
    {
        guard !tracks.isEmpty,
              currentIndex >= 0,
              currentIndex < tracks.count
        else { return nil }
        return tracks[currentIndex]
    }

    var canAdvance: Bool { currentIndex + 1 < tracks.count }
    var canGoBack:  Bool { currentIndex > 0 }

    // Replaces the queue with the given tracks and positions the cursor at
    // `index` (clamped). Used by row-tap: "play this row to end of view".
    // Resets shuffle to off (matches the desktop: a new queue load is treated
    // as a fresh starting point and the user has to opt-in to shuffle again).
    func setQueue(_ newTracks: [Track], startingAt index: Int = 0)
    {
        if isShuffled
        {
            isShuffled = false
            originalTracks.removeAll()
        }
        tracks       = newTracks
        currentIndex = max(0, min(index, max(0, newTracks.count - 1)))
    }

    @discardableResult
    func advance() -> Track?
    {
        guard canAdvance else { return nil }
        currentIndex += 1
        return currentTrack
    }

    @discardableResult
    func goBack() -> Track?
    {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return currentTrack
    }

    @discardableResult
    func jump(to index: Int) -> Track?
    {
        guard index >= 0 && index < tracks.count else { return nil }
        currentIndex = index
        return currentTrack
    }

    // Inserts a track right after the current one. If nothing's playing,
    // appends and positions the cursor on it (the next play call will
    // start there).
    func insertNext(_ track: Track)
    {
        insertNext([track])
    }

    // Inserts a batch of tracks right after the current one, preserving
    // the input order. Used by group-row context menus (long-press an
    // album / artist / genre / playlist row -> "Play Next").
    func insertNext(_ newTracks: [Track])
    {
        guard !newTracks.isEmpty else { return }
        if tracks.isEmpty
        {
            tracks       = newTracks
            currentIndex = 0
        }
        else
        {
            let target = min(currentIndex + 1, tracks.count)
            tracks.insert(contentsOf: newTracks, at: target)
        }
        // Append to the un-shuffled snapshot too so a later unshuffle()
        // still includes the inserted tracks.
        if isShuffled { originalTracks.append(contentsOf: newTracks) }
    }

    // Appends a track at the end of the queue.
    func append(_ track: Track)
    {
        append([track])
    }

    // Appends a batch of tracks at the end, preserving input order.
    func append(_ newTracks: [Track])
    {
        guard !newTracks.isEmpty else { return }
        if tracks.isEmpty
        {
            tracks       = newTracks
            currentIndex = 0
        }
        else
        {
            tracks.append(contentsOf: newTracks)
        }
        if isShuffled { originalTracks.append(contentsOf: newTracks) }
    }

    // MARK: - Shuffle

    // Toggle convenience the transport-bar button calls.
    func setShuffled(_ on: Bool)
    {
        if on { shuffleAll() } else { unshuffle() }
    }

    // Save originalTracks, move the currently-playing track to index 0, then
    // Fisher-Yates shuffle every other track. No-op when nothing's playing
    // (a queue with no current track has nothing meaningful to centre on).
    func shuffleAll()
    {
        guard !tracks.isEmpty,
              currentIndex >= 0,
              currentIndex < tracks.count
        else { return }
        if isShuffled { return }

        originalTracks = tracks
        isShuffled     = true

        var newTracks: [Track] = [tracks[currentIndex]]
        newTracks.reserveCapacity(tracks.count)
        for i in 0 ..< tracks.count where i != currentIndex
        {
            newTracks.append(tracks[i])
        }

        // Fisher-Yates over indices 1...end.
        if newTracks.count > 2
        {
            for i in stride(from: newTracks.count - 1, through: 2, by: -1)
            {
                let j = Int.random(in: 1 ... i)
                newTracks.swapAt(i, j)
            }
        }

        tracks       = newTracks
        currentIndex = 0
    }

    // Restore originalTracks whole, placing the playing track at its
    // original index. Tracks that were ahead of the playing track in the
    // original order come back into "Up Next" (matches the desktop).
    func unshuffle()
    {
        guard isShuffled else { return }
        let playingPath = currentTrack?.filePath

        let restored        = originalTracks
        var restoredIndex   = 0
        if let path = playingPath,
           let idx  = restored.firstIndex(where: { $0.filePath == path })
        {
            restoredIndex = idx
        }

        isShuffled = false
        originalTracks.removeAll()
        tracks       = restored
        currentIndex = restoredIndex
    }

    // MARK: - Repeat

    // off -> all -> one -> off. Bound to the repeat button in the
    // Now Playing sheet, matching the desktop's three-state toggle.
    func cycleRepeatMode()
    {
        switch repeatMode
        {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // Used by AudioPlayer when a track ends naturally (not user-initiated).
    // Encapsulates the desktop's track-finished logic in one place:
    //   - .one: replay current track (returns currentTrack so caller plays it)
    //   - .all: at end, wrap to index 0; otherwise advance
    //   - .off: advance, returns nil at end so caller stops
    @discardableResult
    func advanceForAutoFinish() -> Track?
    {
        switch repeatMode
        {
        case .one:
            return currentTrack

        case .all:
            if canAdvance
            {
                currentIndex += 1
            }
            else if !tracks.isEmpty
            {
                currentIndex = 0
            }
            return currentTrack

        case .off:
            return advance()
        }
    }
}
