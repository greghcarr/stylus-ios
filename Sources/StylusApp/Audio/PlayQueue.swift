import Foundation

// Swift-side play queue: ordered list of tracks plus a current index. Mirrors
// the desktop PlayQueue's surface (advance / goBack / jump / setQueue) but
// not bridged - the C++ version is tied to TrackInfo and the marshalling
// overhead would dominate the trivial logic. Shuffle handling is deferred to
// a later sub-phase.
final class PlayQueue: ObservableObject
{
    @Published private(set) var tracks:       [Track] = []
    @Published private(set) var currentIndex: Int     = 0

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
    func setQueue(_ newTracks: [Track], startingAt index: Int = 0)
    {
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
}
