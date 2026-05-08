import SwiftUI

// Wraps TrackRow in a Button that, on tap, makes `visibleTracks` the new
// queue (positioned at this row) and starts playback. Long-press surfaces
// a context menu (Play Next / Add to Queue / Look up / Edit Info...).
struct TrackRowButton: View
{
    let track:         Track
    let visibleTracks: [Track]
    // Optional overrides forwarded to the underlying TrackRow + the
    // long-press preview's TrackRow. Lets SearchView render track
    // hits as "Artist - Title" with a "Track" subtitle, in place of
    // the standard "Title" + "artist - album" pair.
    var titleOverride:    String? = nil
    var subtitleOverride: String? = nil

    @EnvironmentObject var queue:     PlayQueue
    @EnvironmentObject var audio:     AudioPlayer
    @EnvironmentObject var lookup:    LookupController
    @EnvironmentObject var playlists: PlaylistStore

    @State private var showEdit          = false
    @State private var showAddToPlaylist = false

    var body: some View
    {
        Button
        {
            playFromRow()
        }
        label:
        {
            TrackRow(track:            track,
                     isPlaying:        audio.currentTrack?.filePath == track.filePath,
                     titleOverride:    titleOverride,
                     subtitleOverride: subtitleOverride)
        }
        // RowTapButtonStyle is also responsible for the .plain
        // foreground treatment (overrides Button's default accent
        // tint) plus the press feedback. Replaces the previous
        // .buttonStyle(.plain) + .rowTapFeedback() pair, which used
        // a simultaneousGesture that intercepted List's scroll
        // recognizer.
        .buttonStyle(RowTapButtonStyle())
        // Pin the row separator's leading edge to the cell's leading edge
        // instead of letting SwiftUI infer it from the album-art column.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        // Lock the contextMenu preview's clipping shape so iOS uses
        // the SAME rounded rectangle for both the opening and the
        // dismissing animations. Without this, the system creates
        // a rounded preview when the menu opens, but on dismissal
        // morphs that preview back into the row's natural square
        // shape -- visible briefly as a "rounded becomes straight,
        // slightly larger" frame just before the preview fades out.
        // With the shape pinned, both animations operate on the
        // same rounded rect; the dismissal just shrinks + fades it
        // without changing corner radius.
        .contentShape(.contextMenuPreview,
                      RoundedRectangle(cornerRadius: 12, style: .continuous))
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

            Button
            {
                showAddToPlaylist = true
            }
            label:
            {
                Label("Add to Playlist\u{2026}",
                      systemImage: "text.badge.plus")
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
        // Custom preview view. Without this the system snapshots
        // the source row at its intrinsic content width -- which
        // for TrackRow ends up as just the artwork + title + trailing
        // metadata band, and short-titled rows produce a noticeably
        // narrower preview than long-titled rows. Wrapping a fresh
        // TrackRow with padding + a width cap gives consistent
        // sizing across rows: in portrait the system has enough
        // room to honour the 360 pt cap (so every preview lands at
        // the same width regardless of title length, per the user's
        // request), and in landscape the system reserves part of
        // the screen for the menu's items beside the preview, so
        // we use maxWidth (not a fixed width) to let the preview
        // shrink to the smaller available area instead of having
        // its left + right edges clip. ArtworkCache shares state
        // between this preview instance and the actual list row,
        // so the artwork shows up immediately with no flash.
        preview:
        {
            TrackRow(track:            track,
                     isPlaying:        audio.currentTrack?.filePath == track.filePath,
                     titleOverride:    titleOverride,
                     subtitleOverride: subtitleOverride)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: 360)
        }
        .sheet(isPresented: $showEdit)
        {
            EditInfoView(trackPath: track.filePath)
        }
        .sheet(isPresented: $showAddToPlaylist)
        {
            AddToPlaylistSheet(tracks: [track])
        }
    }

    private func playFromRow()
    {
        let index = visibleTracks.firstIndex(where: { $0.filePath == track.filePath }) ?? 0
        queue.setQueue(visibleTracks, startingAt: index)
        if let t = queue.currentTrack { audio.play(t) }
    }
}
