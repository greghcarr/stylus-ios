import SwiftUI

struct ArtistsView: View
{
    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List
        {
            ForEach(Array(artistRows.enumerated()), id: \.element.name)
            { (index, row) in
                NavigationLink(value: row.name)
                {
                    HStack
                    {
                        Text(row.name)
                        Spacer()
                        Text("\(row.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .hideFirstRowSeparator(index == 0)
                .tracksContextMenu(suggestedName: { row.name })
                                  { tracks(forArtist: row.name) }
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .tabTitleMenu("Artists")
        .navigationDestination(for: String.self)
        { artist in
            ArtistDetailView(artist: artist)
        }
        .overlay
        {
            if artistRows.isEmpty
            {
                EmptyStateView(title: "No artists",
                               systemImage: "music.mic",
                               message: "Tracks will appear here once your library has artists tagged.")
            }
        }
    }

    private var artistRows: [ArtistRow]
    {
        var counts: [String: Int] = [:]
        for t in library.tracks where !t.isPodcast
        {
            guard !t.artist.isEmpty else { continue }
            counts[t.artist, default: 0] += 1
        }
        return counts.map { ArtistRow(name: $0.key, count: $0.value) }
                     .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Same album -> trackNumber -> title ordering ArtistDetailView
    // uses, so a "Play Next" / "Add to Queue" from the artist row
    // matches the order the user would see if they drilled in.
    fileprivate func tracks(forArtist artist: String) -> [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.artist == artist }
            .sorted
            { lhs, rhs in
                if lhs.album.localizedCaseInsensitiveCompare(rhs.album) != .orderedSame
                {
                    return lhs.album.localizedCaseInsensitiveCompare(rhs.album) == .orderedAscending
                }
                if lhs.trackNumber != rhs.trackNumber
                {
                    return lhs.trackNumber < rhs.trackNumber
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    private struct ArtistRow
    {
        let name:  String
        let count: Int
    }
}

// Sentinel key for the "All Albums" entry on ArtistDetailView. Distinct
// type from AlbumKey because pushing AlbumKey already navigates to a
// specific album's track list -- we need a separate destination that
// shows EVERY track for the artist regardless of album, and the
// NavigationStack's value-based push routes by Hashable type.
struct ArtistAllSongsKey: Hashable
{
    let artist: String
}

struct ArtistDetailView: View
{
    let artist: String

    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        // Two presentations:
        //   - 0 or 1 distinct (non-empty) album: skip the album list
        //     entirely and drop the user straight into the track list,
        //     since an intermediate album picker with one entry would
        //     just be busywork.
        //   - 2+ distinct albums: show "All Albums" first followed by
        //     each album in alphabetical order, mirroring iTunes'
        //     classic library navigation.
        Group
        {
            if albumNames.count <= 1
            {
                tracksList
            }
            else
            {
                albumsList
            }
        }
        .navigationTitle(artist)
        .navigationBarTitleDisplayMode(.inline)
        // Both destinations are registered locally on ArtistDetailView
        // so the album-row push and the All-Albums-row push both
        // resolve here rather than fighting AlbumsView's own AlbumKey
        // registration up the stack.
        .navigationDestination(for: AlbumKey.self)
        { key in
            AlbumDetailView(key: key)
        }
        .navigationDestination(for: ArtistAllSongsKey.self)
        { key in
            ArtistAllSongsView(artist: key.artist)
        }
    }

    @ViewBuilder
    private var tracksList: some View
    {
        List
        {
            ForEach(Array(allTracks.enumerated()), id: \.element.id)
            { (index, track) in
                TrackRowButton(track: track, visibleTracks: allTracks)
                    .hideFirstRowSeparator(index == 0)
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var albumsList: some View
    {
        List
        {
            NavigationLink(value: ArtistAllSongsKey(artist: artist))
            {
                HStack(spacing: 12)
                {
                    // Same 44-pt slot the album thumbnails below use,
                    // so the All Albums row's text aligns with the
                    // album-name text rather than hugging the leading
                    // edge.
                    Image(systemName: "square.stack.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                    Text("All Albums")
                    Spacer()
                    Text("\(allTracks.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            // The All Albums row is the first child of this list,
            // so it owns the top-edge separator suppression.
            .hideFirstRowSeparator(true)
            .tracksContextMenu(suggestedName: { artist }) { allTracks }

            ForEach(albumNames, id: \.self)
            { albumName in
                NavigationLink(value: AlbumKey(artist: artist, album: albumName))
                {
                    ArtistAlbumRow(
                        artist:             artist,
                        album:              albumName,
                        trackCount:         trackCount(forAlbum: albumName),
                        representativePath: representativePath(for: albumName)
                    )
                }
                .tracksContextMenu(suggestedName: { albumName })
                                  { tracks(forAlbum: albumName) }
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
    }

    // First track found for the given album by this artist. Used by
    // ArtistAlbumRow as the source for the album-thumb artwork
    // load -- the thumbnail cache keys on path, so any track from
    // the album yields the same image.
    private func representativePath(for albumName: String) -> String?
    {
        library.tracks.first(where:
        { !$0.isPodcast && $0.artist == artist && $0.album == albumName })?
            .filePath
    }

    // All tracks of one specific album (by this artist), sorted by
    // track number then title -- same order AlbumDetailView uses.
    private func tracks(forAlbum albumName: String) -> [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.artist == artist && $0.album == albumName }
            .sorted
            { lhs, rhs in
                if lhs.trackNumber != rhs.trackNumber
                {
                    return lhs.trackNumber < rhs.trackNumber
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    // Distinct non-empty album names tagged on this artist's tracks,
    // sorted alphabetically (case-insensitive). Tracks without an
    // album tag aren't counted as a separate "album" entry; they
    // remain reachable via the All Albums option.
    private var albumNames: [String]
    {
        var seen: Set<String> = []
        var ordered: [String] = []
        for t in library.tracks
        where !t.isPodcast && t.artist == artist && !t.album.isEmpty
        {
            if seen.insert(t.album).inserted { ordered.append(t.album) }
        }
        return ordered.sorted
        { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func trackCount(forAlbum album: String) -> Int
    {
        library.tracks.lazy
            .filter { !$0.isPodcast && $0.artist == artist && $0.album == album }
            .count
    }

    // All tracks for this artist (any album, including empty-album
    // tracks). Sorted by album → track number → title for stable
    // playback ordering when the user taps a row to start the queue.
    private var allTracks: [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.artist == artist }
            .sorted
            { lhs, rhs in
                if lhs.album.localizedCaseInsensitiveCompare(rhs.album) != .orderedSame
                {
                    return lhs.album.localizedCaseInsensitiveCompare(rhs.album) == .orderedAscending
                }
                if lhs.trackNumber != rhs.trackNumber
                {
                    return lhs.trackNumber < rhs.trackNumber
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }
}

// Row used by ArtistDetailView's albumsList for each specific album
// by the artist. Shows a 44-pt artwork thumbnail on the leading
// edge, the album title in the middle, and the per-album track
// count on the trailing edge. ArtworkCache shares state with every
// other AlbumRow / TrackRow that loads this same path, so scrolling
// is flash-free even on first paint.
private struct ArtistAlbumRow: View
{
    let artist:             String
    let album:              String
    let trackCount:         Int
    let representativePath: String?

    @State private var artwork: UIImage?

    var body: some View
    {
        HStack(spacing: 12)
        {
            artworkThumb
            Text(album).lineLimit(1)
            Spacer()
            Text("\(trackCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .task(id: representativePath)
        {
            guard let p = representativePath else { return }
            artwork = await loadThumbnail(for: p)
        }
    }

    @ViewBuilder
    private var artworkThumb: some View
    {
        Group
        {
            if let artwork = artwork
            {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            else
            {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: "square.stack")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// "All Albums" leaf view: every track by the given artist, ordered the
// same way ArtistDetailView orders its tracksList. Reached only from
// the multi-album presentation in ArtistDetailView.
struct ArtistAllSongsView: View
{
    let artist: String

    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List
        {
            ForEach(Array(tracks.enumerated()), id: \.element.id)
            { (index, track) in
                TrackRowButton(track: track, visibleTracks: tracks)
                    .hideFirstRowSeparator(index == 0)
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .navigationTitle("All Albums")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tracks: [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.artist == artist }
            .sorted
            { lhs, rhs in
                if lhs.album.localizedCaseInsensitiveCompare(rhs.album) != .orderedSame
                {
                    return lhs.album.localizedCaseInsensitiveCompare(rhs.album) == .orderedAscending
                }
                if lhs.trackNumber != rhs.trackNumber
                {
                    return lhs.trackNumber < rhs.trackNumber
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }
}
