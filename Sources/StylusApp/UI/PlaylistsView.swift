import SwiftUI

// Typed wrapper for value-based NavigationStack push from
// PlaylistsView -> PlaylistDetailView. Plain Int would collide with
// other String/Int destinations registered up the stack; this keeps
// the routing unambiguous.
struct PlaylistKey: Hashable
{
    let id: Int
}

struct PlaylistsView: View
{
    @EnvironmentObject var playlists: PlaylistStore
    @EnvironmentObject var library:   LibraryStore

    @State private var showCreateAlert: Bool   = false
    @State private var newPlaylistName: String = ""

    var body: some View
    {
        List
        {
            ForEach(Array(playlists.playlists.enumerated()), id: \.element.id)
            { (index, playlist) in
                NavigationLink(value: PlaylistKey(id: playlist.id))
                {
                    HStack(spacing: 12)
                    {
                        Image(systemName: "list.bullet.rectangle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(playlist.name).lineLimit(1)
                        Spacer()
                        Text("\(playlist.trackPaths.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                // Pin the separator's leading edge to the cell's
                // leading edge so the divider extends symmetrically
                // (without this it inset to where the row's content
                // begins, leaving a visible gap on the left).
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(index == 0)
                .tracksContextMenu(
                    suggestedName: { playlist.name },
                    tracksFor:     { resolvedTracks(for: playlist) }
                )
                {
                    Divider()
                    Button(role: .destructive)
                    {
                        playlists.deletePlaylist(id: playlist.id)
                    }
                    label:
                    {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                }
            }
            .onDelete
            { offsets in
                playlists.deletePlaylists(at: offsets)
            }
            .onMove
            { source, destination in
                playlists.movePlaylists(from: source, to: destination)
            }

            // "New Playlist" action row sits BELOW the existing
            // playlists -- iOS-Music style, where the create-action
            // is at the bottom of the list rather than competing
            // with the user's existing items at the top.
            Button
            {
                newPlaylistName = ""
                showCreateAlert = true
            }
            label:
            {
                HStack(spacing: 12)
                {
                    // .secondary (grey) rather than .tint (blue) so
                    // the icon reads as a list-row affordance rather
                    // than a primary-action accent. The text stays
                    // primary-coloured via RowTapButtonStyle.
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    Text("New Playlist")
                    Spacer()
                }
            }
            .buttonStyle(RowTapButtonStyle())
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            // When the playlist list is empty this is the very first
            // row; otherwise its top separator is the boundary with
            // the last playlist row above it (still wanted, so leave
            // hideFirstRowSeparator off).
            .hideFirstRowSeparator(playlists.playlists.isEmpty)

            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .tabTitleMenu("Playlists")
        .navigationDestination(for: PlaylistKey.self)
        { key in
            PlaylistDetailView(playlistId: key.id)
        }
        .overlay
        {
            if playlists.playlists.isEmpty
            {
                EmptyStateView(
                    title:       "No playlists",
                    systemImage: "list.bullet.rectangle",
                    message:     "Tap New Playlist above to create one. Then long-press any track and choose Add to Playlist."
                )
            }
        }
        // Native iOS new-playlist alert. Using .alert keeps the
        // text-input UX standard (system keyboard, Cancel / Create
        // buttons, escape-to-cancel) without us hand-rolling a sheet.
        .alert("New Playlist", isPresented: $showCreateAlert)
        {
            TextField("Name", text: $newPlaylistName)
            Button("Create")
            {
                let trimmed = newPlaylistName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty
                {
                    playlists.createPlaylist(name: trimmed)
                }
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel)
            {
                newPlaylistName = ""
            }
        }
        message:
        {
            Text("Name your new playlist.")
        }
    }

    // Resolve a playlist's stored file paths against the live library,
    // preserving the playlist's ordering and dropping orphans whose
    // files have left the library. Same logic the playlist-detail
    // view uses for its display.
    private func resolvedTracks(for playlist: Playlist) -> [Track]
    {
        playlist.trackPaths.compactMap
        { path in
            library.tracks.first(where: { $0.filePath == path })
        }
    }
}

struct PlaylistDetailView: View
{
    let playlistId: Int

    @EnvironmentObject var playlists: PlaylistStore
    @EnvironmentObject var library:   LibraryStore

    @State private var showRenameAlert: Bool   = false
    @State private var renameValue:     String = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View
    {
        // playlist might disappear if the user deleted it from
        // another surface; render an empty state in that case
        // rather than crashing on a force-unwrap.
        let playlist = playlists.playlists.first { $0.id == playlistId }

        Group
        {
            if let p = playlist
            {
                listBody(for: p)
            }
            else
            {
                EmptyStateView(title:       "Playlist not found",
                               systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar
        {
            // Trailing: Edit (drag-to-reorder + swipe-to-delete tracks).
            ToolbarItem(placement: .topBarTrailing)
            {
                EditButton()
            }
            // Plus a small overflow with rename / delete-playlist
            // since the stock libraryActionsToolbar isn't applied here
            // (this is a leaf view, not a tab root).
            ToolbarItem(placement: .topBarTrailing)
            {
                Menu
                {
                    Button
                    {
                        renameValue     = playlist?.name ?? ""
                        showRenameAlert = true
                    }
                    label:
                    {
                        Label("Rename Playlist\u{2026}", systemImage: "pencil")
                    }

                    Button(role: .destructive)
                    {
                        if let id = playlist?.id
                        {
                            playlists.deletePlaylist(id: id)
                            dismiss()
                        }
                    }
                    label:
                    {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                }
                label:
                {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Playlist", isPresented: $showRenameAlert)
        {
            TextField("Name", text: $renameValue)
            Button("Save")
            {
                let trimmed = renameValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let id = playlist?.id
                {
                    playlists.renamePlaylist(id: id, to: trimmed)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    @ViewBuilder
    private func listBody(for playlist: Playlist) -> some View
    {
        // Pair each visible Track with its index in the playlist's
        // backing trackPaths array. The .onDelete / .onMove offsets
        // come back as indices into THIS displayed array; we
        // translate them through `originalIndex` to keep the
        // playlist's stored ordering accurate even if some tracks
        // are missing from the library (orphans hidden from view).
        let entries = displayEntries(for: playlist)
        let visibleTracks = entries.map(\.track)

        List
        {
            ForEach(Array(entries.enumerated()), id: \.element.track.id)
            { (rowIndex, entry) in
                TrackRowButton(track: entry.track, visibleTracks: visibleTracks)
                    .hideFirstRowSeparator(rowIndex == 0)
            }
            .onDelete
            { offsets in
                let storedIndices = offsets.map { entries[$0].originalIndex }
                playlists.removeTrackPaths(at: IndexSet(storedIndices),
                                           from: playlist.id)
            }
            .onMove
            { source, destination in
                // Move on the FULL trackPaths array, not the visible
                // subset. We translate the visible source/destination
                // into stored indices to keep orphaned paths in place.
                let storedSource = IndexSet(source.map { entries[$0].originalIndex })
                let storedDestination: Int
                if destination >= entries.count
                {
                    storedDestination = playlist.trackPaths.count
                }
                else
                {
                    storedDestination = entries[destination].originalIndex
                }
                playlists.moveTrackPaths(from:        storedSource,
                                         to:          storedDestination,
                                         in:          playlist.id)
            }

            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .overlay
        {
            if entries.isEmpty
            {
                EmptyStateView(
                    title:       "No tracks",
                    systemImage: "music.note.list",
                    message:     "Long-press a track anywhere in the app and choose Add to Playlist to add it here."
                )
            }
        }
    }

    private struct DisplayEntry
    {
        let originalIndex: Int   // index into Playlist.trackPaths
        let track:         Track
    }

    // Map each path to a Track (skipping orphans whose files are no
    // longer in the library). Preserving the originalIndex lets edits
    // operate on the storage-level path list, not just the visible
    // subset.
    private func displayEntries(for playlist: Playlist) -> [DisplayEntry]
    {
        playlist.trackPaths.enumerated().compactMap
        { (index, path) in
            guard let track = library.tracks.first(where: { $0.filePath == path })
            else { return nil }
            return DisplayEntry(originalIndex: index, track: track)
        }
    }
}

// "Add to Playlist..." sheet, presented from any row's context menu
// (single track from TrackRowButton, or a batch of tracks from an
// album / artist / genre / podcast / playlist row). Lists existing
// playlists and offers a quick path to create a new one inline.
// Tapping a playlist appends every track in `tracks` and dismisses
// immediately.
struct AddToPlaylistSheet: View
{
    let tracks:        [Track]
    // Pre-fill for the "New Playlist" name field, used so a long-
    // press on an album / artist / genre / podcast / playlist row
    // suggests that group's name as the playlist title. Empty
    // string means no suggestion (the field opens blank, as it
    // does for single-track adds).
    let suggestedName: String

    @EnvironmentObject var playlists: PlaylistStore
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateAlert: Bool   = false
    @State private var newPlaylistName: String = ""

    var body: some View
    {
        NavigationStack
        {
            List
            {
                Button
                {
                    // Seed the alert's text field with whatever the
                    // call site suggested (the album name, artist,
                    // playlist name, etc.). If nothing was passed,
                    // it opens blank.
                    newPlaylistName = suggestedName
                    showCreateAlert = true
                }
                label:
                {
                    HStack(spacing: 12)
                    {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                        Text("New Playlist")
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }

                ForEach(playlists.playlists)
                { playlist in
                    Button
                    {
                        playlists.addTracks(tracks.map(\.filePath),
                                            to: playlist.id)
                        dismiss()
                    }
                    label:
                    {
                        HStack(spacing: 12)
                        {
                            Image(systemName: "list.bullet.rectangle.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text(playlist.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if allTracksInPlaylist(playlist)
                            {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .font(.caption.weight(.bold))
                            }
                            Text("\(playlist.trackPaths.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {
                ToolbarItem(placement: .topBarLeading)
                {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $showCreateAlert)
            {
                TextField("Name", text: $newPlaylistName)
                Button("Create")
                {
                    let trimmed = newPlaylistName
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty
                    {
                        let p = playlists.createPlaylist(name: trimmed)
                        playlists.addTracks(tracks.map(\.filePath), to: p.id)
                        dismiss()
                    }
                    newPlaylistName = ""
                }
                Button("Cancel", role: .cancel)
                {
                    newPlaylistName = ""
                }
            }
            message:
            {
                Text(createMessage)
            }
        }
    }

    // Convenience for callers that already have a single Track.
    // Single-track adds default to no suggestion since "Bohemian
    // Rhapsody" makes a poor playlist name; group adds (album,
    // artist, genre, etc.) supply their own group name through the
    // [Track] init.
    init(track: Track,
         suggestedName: String = "")
    {
        self.tracks        = [track]
        self.suggestedName = suggestedName
    }

    init(tracks: [Track],
         suggestedName: String = "")
    {
        self.tracks        = tracks
        self.suggestedName = suggestedName
    }

    // Show the checkmark only when EVERY track is already a member of
    // the playlist. For a single-track call this matches the prior
    // behaviour; for a batch it answers "is this whole album/artist
    // already in here?" with a simple yes/no.
    private func allTracksInPlaylist(_ playlist: Playlist) -> Bool
    {
        guard !tracks.isEmpty else { return false }
        let pathSet = Set(playlist.trackPaths)
        return tracks.allSatisfy { pathSet.contains($0.filePath) }
    }

    private var createMessage: String
    {
        switch tracks.count
        {
        case 1:
            return "Name your new playlist; this track will be added."
        default:
            return "Name your new playlist; these \(tracks.count) tracks will be added."
        }
    }
}
