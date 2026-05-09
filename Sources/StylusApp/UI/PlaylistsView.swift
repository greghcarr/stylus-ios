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
    @EnvironmentObject        var playlists: PlaylistStore
    @EnvironmentObject        var library:   LibraryStore
    @Environment(\.tabRouter) private var router

    @State private var showCreateAlert: Bool   = false
    @State private var newPlaylistName: String = ""

    var body: some View
    {
        List
        {
            ForEach(Array(playlists.playlists.enumerated()), id: \.element.id)
            { (index, playlist) in
                Button
                {
                    router?.path.append(PlaylistKey(id: playlist.id))
                }
                label:
                {
                    CompositeArtworkRow(
                        representativePaths: representativePaths(for: playlist),
                        title:               playlist.name,
                        count:               playlist.trackPaths.count
                    )
                }
                .buttonStyle(RowTapButtonStyle())
                // Pin the separator's leading edge to the cell's
                // leading edge so the divider extends symmetrically
                // (without this it inset to where the row's content
                // begins, leaving a visible gap on the left).
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(index == 0)
                .tracksContextMenu(
                    suggestedName: { playlist.name },
                    tracksFor:     { resolvedTracks(for: playlist) },
                    preview: {
                        CompositeArtworkRow(
                            representativePaths: representativePaths(for: playlist),
                            title:               playlist.name,
                            count:               playlist.trackPaths.count
                        )
                    },
                    additionalItems: {
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
                )
            }
            .onMove
            { source, destination in
                playlists.movePlaylists(from: source, to: destination)
            }

            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .tabTitleMenu("Playlists")
        // Trailing overflow menu. Single entry today (Create Playlist);
        // future per-tab actions go here too. SwiftUI Menu rather than
        // the UIDeferredMenuElement-backed UIButton other tabs use,
        // because PlaylistsView doesn't see the high-frequency parent
        // re-renders during library scan that motivated the UIKit
        // workaround there.
        .toolbar
        {
            ToolbarItem(placement: .topBarTrailing)
            {
                Menu
                {
                    Button
                    {
                        newPlaylistName = ""
                        showCreateAlert = true
                    }
                    label:
                    {
                        Label("Create Playlist",
                              systemImage: "plus.circle.fill")
                    }
                }
                label:
                {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
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
                    message:     "Tap the menu in the upper-right and choose Create Playlist. Then long-press any track and choose Add to Playlist."
                )
            }
        }
        // Native iOS create-playlist alert. Using .alert keeps the
        // text-input UX standard (system keyboard, Cancel / Create
        // buttons, escape-to-cancel) without us hand-rolling a sheet.
        .alert("Create Playlist", isPresented: $showCreateAlert)
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
            Text("Name your playlist.")
        }
    }

    // Resolve a playlist's stored file paths against the live library,
    // preserving the playlist's ordering and dropping orphans whose
    // files have left the library. Same logic the playlist-detail
    // view uses for its display.
    private func resolvedTracks(for playlist: Playlist) -> [Track]
    {
        let (byPath, byTail) = libraryLookupTables()
        return playlist.trackPaths.compactMap
        { path in
            byPath[path]
                ?? byTail[PlaylistDetailView.sandboxRelativeTail(path)]
        }
    }

    // Up to 8 representative file paths from this playlist (one per
    // distinct (artist, album) pair encountered in playlist order),
    // feeding the row's CompositeArtworkThumb. Walks trackPaths
    // sequentially so the first-seen track of each album wins, and
    // stops once we've collected 8 -- enough to give the composite
    // 4 successful thumbnail loads with margin for albums that have
    // no artwork.
    //
    // Resolves stale-container paths via the same sandbox-relative-
    // tail fallback PlaylistDetailView uses, then returns the
    // CURRENT library path so the artwork load hits the right file.
    private func representativePaths(for playlist: Playlist) -> [String]
    {
        let (byPath, byTail) = libraryLookupTables()
        var seen: Set<String> = []
        var paths: [String] = []
        for storedPath in playlist.trackPaths
        {
            let track = byPath[storedPath]
                ?? byTail[PlaylistDetailView.sandboxRelativeTail(storedPath)]
            guard let track = track else { continue }
            let albumKey = track.artist + "\u{1F}" + track.album
            if seen.insert(albumKey).inserted
            {
                paths.append(track.filePath)
                if paths.count >= 8 { break }
            }
        }
        return paths
    }

    private func libraryLookupTables() -> (byPath: [String: Track],
                                            byTail: [String: Track])
    {
        var byPath: [String: Track] = [:]
        var byTail: [String: Track] = [:]
        for track in library.tracks
        {
            byPath[track.filePath] = track
            let tail = PlaylistDetailView.sandboxRelativeTail(track.filePath)
            if tail != track.filePath
            {
                byTail[tail] = track
            }
        }
        return (byPath, byTail)
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
            // Trailing: Edit (drag-to-reorder tracks). Removal
            // happens via the long-press contextMenu's "Remove from
            // Playlist" item -- swipe-to-delete was removed because
            // outside-table taps didn't dismiss the revealed
            // trash button (standard UIKit behaviour, but felt
            // broken to the user).
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
                TrackRowButton(
                    track:         entry.track,
                    visibleTracks: visibleTracks,
                    onRemoveFromPlaylist:
                    {
                        playlists.removeTrackPaths(
                            at:   IndexSet([entry.originalIndex]),
                            from: playlist.id
                        )
                    }
                )
                .hideFirstRowSeparator(rowIndex == 0)
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
    //
    // Lookup is two-pass: first by exact filePath match (fast), then
    // by the path's iOS-sandbox-relative tail. The tail fallback
    // handles the case where a track was added to a playlist under
    // an older app data-container UUID; iOS reassigns that UUID on
    // some installs / restores, leaving the stored playlist paths
    // pointing at a directory the current install no longer uses.
    // Same files / same relative structure, just a different
    // container-prefix, so matching on the post-UUID tail finds them.
    private func displayEntries(for playlist: Playlist) -> [DisplayEntry]
    {
        let (byPath, byTail) = libraryLookupTables()

        return playlist.trackPaths.enumerated().compactMap
        { (index, path) in
            if let track = byPath[path]
            {
                return DisplayEntry(originalIndex: index, track: track)
            }
            let tail = Self.sandboxRelativeTail(path)
            if let track = byTail[tail]
            {
                return DisplayEntry(originalIndex: index, track: track)
            }
            return nil
        }
    }

    // Builds two lookup tables over library.tracks in one pass,
    // keyed by full path and by sandbox-relative tail. Used by
    // displayEntries to do the two-stage lookup without making
    // it O(N x M) over the playlist size.
    private func libraryLookupTables() -> (byPath: [String: Track],
                                            byTail: [String: Track])
    {
        var byPath: [String: Track] = [:]
        var byTail: [String: Track] = [:]
        for track in library.tracks
        {
            byPath[track.filePath] = track
            let tail = Self.sandboxRelativeTail(track.filePath)
            if tail != track.filePath
            {
                byTail[tail] = track
            }
        }
        return (byPath, byTail)
    }

    // Strips the iOS app-sandbox container prefix from a path,
    // returning everything from the directory after the container
    // UUID onwards. For a typical iOS path like
    //   /private/var/mobile/Containers/Data/Application/<UUID>/Documents/...
    // returns
    //   Documents/...
    // For a path that doesn't carry the sandbox marker the original
    // path is returned unchanged -- so two non-sandbox paths still
    // compare exactly.
    fileprivate static func sandboxRelativeTail(_ path: String) -> String
    {
        guard let containers = path.range(of: "/Containers/Data/Application/")
        else { return path }
        let afterMarker = path[containers.upperBound...]
        guard let firstSlash = afterMarker.firstIndex(of: "/")
        else { return path }
        return String(afterMarker[afterMarker.index(after: firstSlash)...])
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
    // Pre-fill for the "Create Playlist" name field, used so a long-
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
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }

                // "Create Playlist" sits at the bottom of the list,
                // matching the Playlists tab itself -- the create-
                // action goes BELOW the user's existing playlists
                // rather than competing with them at the top.
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
                        // .tint (blue) reads as a primary "create"
                        // action against the otherwise-grey existing-
                        // playlist rows.
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                        Text("Create Playlist")
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
            .alert("Create Playlist", isPresented: $showCreateAlert)
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
            return "Name your playlist; this track will be added."
        default:
            return "Name your playlist; these \(tracks.count) tracks will be added."
        }
    }
}
