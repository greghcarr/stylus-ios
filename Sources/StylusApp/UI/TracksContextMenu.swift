import SwiftUI

extension View
{
    // No-extras variant: Play Next / Add to Queue / Add to Playlist...
    // entries plus a custom rounded preview matching the row's
    // content. preview is required so every row type that uses this
    // modifier gets the same long-press visual as TrackRowButton.
    func tracksContextMenu<Preview: View>(
        suggestedName: @escaping () -> String  = { "" },
        tracksFor:     @escaping () -> [Track],
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View
    {
        tracksContextMenu(suggestedName: suggestedName,
                          tracksFor:     tracksFor,
                          preview:       preview)
        {
            EmptyView()
        }
    }

    // Variant that appends caller-supplied items below the standard
    // three (used by playlist rows for the destructive Delete entry).
    // preview is required for the same reason as above.
    func tracksContextMenu<Preview: View, Extra: View>(
        suggestedName: @escaping () -> String  = { "" },
        tracksFor:     @escaping () -> [Track],
        @ViewBuilder preview:         @escaping () -> Preview,
        @ViewBuilder additionalItems: @escaping () -> Extra
    ) -> some View
    {
        modifier(TracksContextMenu(suggestedName:    suggestedName,
                                   tracksFor:        tracksFor,
                                   previewContent:   preview,
                                   additionalItems:  additionalItems))
    }
}

// `tracksFor` is called lazily when a menu item is tapped so any
// expensive filtering / sorting only runs at action time.
//
// `suggestedName` provides a default value for the Create Playlist
// alert's name field.
//
// `previewContent` is the row's content rendered fresh for the
// long-press preview; the modifier wraps it in consistent padding +
// a 360-pt max width so every row in the app long-presses to the
// same shape and size, matching TrackRowButton's behaviour.
//
// .contentShape(.contextMenuPreview, RoundedRectangle) locks the
// preview's clipping shape so iOS doesn't morph rounded -> square
// on dismissal. Same fix TrackRowButton uses.
private struct TracksContextMenu<Preview: View, Extra: View>: ViewModifier
{
    let suggestedName:    () -> String
    let tracksFor:        () -> [Track]
    let previewContent:   () -> Preview
    let additionalItems:  () -> Extra

    @EnvironmentObject var queue: PlayQueue

    @State private var showAddToPlaylist: Bool    = false
    @State private var pendingTracks:     [Track] = []
    @State private var pendingName:       String  = ""

    func body(content: Content) -> some View
    {
        content
            .contentShape(.contextMenuPreview,
                          RoundedRectangle(cornerRadius: 12,
                                           style:        .continuous))
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
            preview:
            {
                previewContent()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 360)
            }
            .sheet(isPresented: $showAddToPlaylist)
            {
                AddToPlaylistSheet(tracks:        pendingTracks,
                                   suggestedName: pendingName)
            }
    }
}
