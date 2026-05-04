import SwiftUI

// Wraps TrackRow in a Button that, on tap, makes `visibleTracks` the new
// queue (positioned at this row) and starts playback. Long-press surfaces
// a context menu (Play Next / Add to Queue / Look up / Edit Info...).
struct TrackRowButton: View
{
    let track:         Track
    let visibleTracks: [Track]

    @EnvironmentObject var queue:  PlayQueue
    @EnvironmentObject var audio:  AudioPlayer
    @EnvironmentObject var lookup: LookupController

    @State private var showEdit = false

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
        // Pin the row separator's leading edge to the cell's leading edge
        // instead of letting SwiftUI infer it from the album-art column.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .contextMenu
        {
            Button
            {
                queue.insertNext(track)
            }
            label:
            {
                Label("Play Next", systemImage: "text.insert")
            }

            Button
            {
                queue.append(track)
            }
            label:
            {
                Label("Add to Queue", systemImage: "text.append")
            }

            Divider()

            Button
            {
                lookup.enqueue(track, overwrite: false)
            }
            label:
            {
                Label("Look up on iTunes", systemImage: "magnifyingglass")
            }

            Button
            {
                showEdit = true
            }
            label:
            {
                Label("Edit Info\u{2026}", systemImage: "info.circle")
            }
        }
        .sheet(isPresented: $showEdit)
        {
            EditInfoView(trackPath: track.filePath)
        }
    }

    private func playFromRow()
    {
        let index = visibleTracks.firstIndex(where: { $0.filePath == track.filePath }) ?? 0
        queue.setQueue(visibleTracks, startingAt: index)
        if let t = queue.currentTrack { audio.play(t) }
    }
}
