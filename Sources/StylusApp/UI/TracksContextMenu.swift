import SwiftUI

extension View
{
    // No-extras variant: just the standard three entries (Play Next /
    // Add to Queue / Add to Playlist...).
    func tracksContextMenu(suggestedName: @escaping () -> String  = { "" },
                           tracksFor:     @escaping () -> [Track]) -> some View
    {
        tracksContextMenu(suggestedName: suggestedName,
                          tracksFor:     tracksFor)
        {
            EmptyView()
        }
    }

    // Variant that appends caller-supplied items below the standard
    // three. Used by the playlist-row long-press menu to add a
    // destructive "Delete Playlist" action; nothing else needs the
    // extra slot today, but the hook is generic so other surfaces
    // (e.g. "Remove Album" later) can plug in without a second
    // helper.
    //
    // Splitting into two overloads avoids the Swift limitation where
    // a generic @ViewBuilder closure can't carry a meaningful
    // default value.
    func tracksContextMenu<Extra: View>(
        suggestedName: @escaping () -> String = { "" },
        tracksFor:     @escaping () -> [Track],
        @ViewBuilder additionalItems: @escaping () -> Extra
    ) -> some View
    {
        modifier(TracksContextMenu(suggestedName:    suggestedName,
                                   tracksFor:        tracksFor,
                                   additionalItems:  additionalItems))
    }
}

// `tracksFor` is called lazily when a menu item is tapped so any
// expensive filtering / sorting only runs at action time.
//
// `suggestedName` provides a default value for the New Playlist
// alert's name field when the user picks "Add to Playlist..." ->
// "New Playlist". Each call site passes the row's contextual name
// (album title, artist, genre, etc.) so the alert opens pre-filled
// with it.
//
// TrackRowButton has its own contextMenu with the same three core
// entries plus Look up on iTunes / Edit Info..., so it doesn't use
// this helper -- but the wording and ordering of the shared entries
// match here so the menu feels consistent across row types.
private struct TracksContextMenu<Extra: View>: ViewModifier
{
    let suggestedName:    () -> String
    let tracksFor:        () -> [Track]
    let additionalItems:  () -> Extra

    @EnvironmentObject var queue: PlayQueue

    @State private var showAddToPlaylist: Bool    = false
    @State private var pendingTracks:     [Track] = []
    @State private var pendingName:       String  = ""

    func body(content: Content) -> some View
    {
        content
            .contextMenu
            {
                Button
                {
                    queue.insertNext(tracksFor())
                }
                label:
                {
                    Label("Play Next", systemImage: "text.insert")
                }

                Button
                {
                    queue.append(tracksFor())
                }
                label:
                {
                    Label("Add to Queue", systemImage: "text.append")
                }

                Button
                {
                    pendingTracks     = tracksFor()
                    pendingName       = suggestedName()
                    showAddToPlaylist = true
                }
                label:
                {
                    Label("Add to Playlist\u{2026}",
                          systemImage: "text.badge.plus")
                }

                additionalItems()
            }
            .sheet(isPresented: $showAddToPlaylist)
            {
                AddToPlaylistSheet(tracks:        pendingTracks,
                                   suggestedName: pendingName)
            }
    }
}
