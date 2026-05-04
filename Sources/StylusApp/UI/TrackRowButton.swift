import SwiftUI

// Wraps TrackRow in a Button that, on tap, makes `visibleTracks` the new
// queue (positioned at this row) and starts playback. Mirrors the desktop
// rule "tap a row, queue this row to end of view".
struct TrackRowButton: View
{
    let track:         Track
    let visibleTracks: [Track]

    @EnvironmentObject var queue: PlayQueue
    @EnvironmentObject var audio: AudioPlayer

    var body: some View
    {
        Button
        {
            playFromRow()
        }
        label:
        {
            TrackRow(track: track,
                     isPlaying: audio.currentTrack?.filePath == track.filePath)
        }
        .buttonStyle(.plain)
    }

    private func playFromRow()
    {
        let index = visibleTracks.firstIndex(where: { $0.filePath == track.filePath }) ?? 0
        queue.setQueue(visibleTracks, startingAt: index)
        if let t = queue.currentTrack { audio.play(t) }
    }
}
