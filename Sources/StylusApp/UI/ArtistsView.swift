import SwiftUI

// MARK: - Navigation marker types
//
// These exist purely to give the NavigationStack a typed destination
// for value-based pushes. Marker structs (no fields) work the same as
// proper data types for routing purposes; they just make the
// destination registrations unambiguous when more than one push of a
// given semantic role is in play.

// "All Artists" -> AllArtistsView (the album-list intermediate).
struct AllArtistsKey: Hashable { }

// "All Albums" inside AllArtistsView -> AllSongsView (every music track).
// Distinct from ArtistAllSongsKey (which is "all songs BY a specific
// artist"); this one is library-wide.
struct AllSongsKey: Hashable { }

// "(no album)" inside AllArtistsView or AlbumsView -> tracks with
// empty album tag across every artist. Distinct from
// AlbumKey(artist, "") which is "tracks by a specific artist with
// empty album"; this one is global.
struct NoAlbumKey: Hashable { }

// "(no genre)" inside GenresView -> tracks with empty genre tag.
// Defined here for symmetry with the other untagged-category keys
// even though it's used by GenresView, since the navigation
// vocabulary for "untagged X" is part of the same library-browsing
// design pattern.
struct NoGenreKey: Hashable { }

// Sentinel key for the "All Albums" entry inside ArtistDetailView's
// per-artist drilldown. Distinct from AlbumKey because pushing
// AlbumKey already navigates to a specific album's track list -- we
// need a separate destination that shows EVERY track for the artist
// regardless of album, and the NavigationStack's value-based push
// routes by Hashable type.
struct ArtistAllSongsKey: Hashable
{
    let artist: String
}

// MARK: - ArtistsView (Artists tab top-level)

struct ArtistsView: View
{
    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List
        {
            // "All Artists" sits at the top, mirroring iTunes' top-of-
            // sidebar entry, then the alphabetised artists. Hidden
            // when there are no artists at all (empty-state overlay
            // takes over).
            if !artistRows.isEmpty
            {
                NavigationLink(value: AllArtistsKey())
                {
                    HStack
                    {
                        Text("All Artists")
                        Spacer()
                        Text("\(allMusicTracks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(true)
                .tracksContextMenu(suggestedName: { "All Artists" })
                                  { allMusicTracks }
            }

            // "(no artist)" -- italics to flag this as a special
            // category rather than a real artist name. Hidden when
            // every track in the library has an artist tag.
            // Pushes the empty-string artist value through the
            // existing ArtistDetailView destination, which handles
            // the artist == "" filter naturally.
            if !noArtistTracks.isEmpty
            {
                NavigationLink(value: "")
                {
                    HStack
                    {
                        Text("(no artist)").italic()
                        Spacer()
                        Text("\(noArtistTracks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .tracksContextMenu(suggestedName: { "" })
                                  { noArtistTracks }
            }

            ForEach(artistRows, id: \.name)
            { row in
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
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
        .navigationDestination(for: AllArtistsKey.self)
        { _ in
            AllArtistsView()
        }
        .overlay
        {
            if artistRows.isEmpty && noArtistTracks.isEmpty
            {
                EmptyStateView(title: "No artists",
                               systemImage: "music.mic",
                               message: "Tracks will appear here once your library has artists tagged.")
            }
        }
    }

    // Distinct non-empty artist names with track counts. Tracks with
    // empty artist tag are NOT bucketed here -- they're surfaced
    // through the "(no artist)" sentinel above so the alphabetical
    // list stays free of empty-string entries.
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

    // Every music track in the library, ignoring podcasts. Used by
    // the All Artists row's count display and tracksContextMenu.
    fileprivate var allMusicTracks: [Track]
    {
        library.tracks.filter { !$0.isPodcast }
    }

    // Tracks with no artist tag (empty string). The "(no artist)"
    // sentinel only renders when this is non-empty.
    fileprivate var noArtistTracks: [Track]
    {
        library.tracks.filter { !$0.isPodcast && $0.artist.isEmpty }
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

// MARK: - ArtistDetailView (per-artist drilldown)

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
        //     "(no album)" if any of this artist's tracks lack an
        //     album tag, then each album in alphabetical order --
        //     iTunes' classic library navigation.
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
        .navigationTitle(artist.isEmpty ? "(no artist)" : artist)
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
            // "All Albums" -- existing behaviour, reaches every
            // track for this artist regardless of album tag.
            NavigationLink(value: ArtistAllSongsKey(artist: artist))
            {
                HStack(spacing: 12)
                {
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
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .hideFirstRowSeparator(true)
            .tracksContextMenu(suggestedName: { artist }) { allTracks }

            // "(no album)" -- only when this artist has tracks
            // without an album tag. Pushes AlbumKey(artist, "")
            // which AlbumDetailView already filters correctly
            // (album == "" AND artist == this artist).
            if !noAlbumTracks.isEmpty
            {
                NavigationLink(value: AlbumKey(artist: artist, album: ""))
                {
                    HStack(spacing: 12)
                    {
                        // Same 44-pt slot the album thumbnails below
                        // use, so the row's text aligns vertically
                        // with the album-name text.
                        Image(systemName: "square.dashed")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                        Text("(no album)").italic()
                        Spacer()
                        Text("\(noAlbumTracks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .tracksContextMenu(suggestedName: { "" }) { noAlbumTracks }
            }

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
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
    // album tag aren't counted here; they surface via the
    // "(no album)" sentinel and the All Albums catch-all.
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

    // This artist's tracks where album is empty -- drives the
    // "(no album)" sentinel.
    private var noAlbumTracks: [Track]
    {
        library.tracks.filter
        { !$0.isPodcast && $0.artist == artist && $0.album.isEmpty }
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

// MARK: - ArtistAlbumRow (per-album row inside ArtistDetailView)

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

// MARK: - ArtistAllSongsView ("All Albums" leaf inside ArtistDetailView)

// Every track by the given artist, ordered the same way
// ArtistDetailView orders its tracksList. Reached only from the
// multi-album presentation in ArtistDetailView.
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

// MARK: - AllArtistsView ("All Artists" leaf — album list)

// Reached from the Artists tab's "All Artists" row. Shows every
// distinct (artist, album) pair in the library, with an "All
// Albums" sentinel at the top that drops the user into a flat all-
// songs view, plus a "(no album)" sentinel for tracks across all
// artists that lack an album tag. Mirrors AlbumsView's structure
// closely; the difference is that this view also offers the All
// Albums + (no album) sentinels at the top, where AlbumsView is
// reached as a top-level tab and stays a pure album list.
struct AllArtistsView: View
{
    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List
        {
            NavigationLink(value: AllSongsKey())
            {
                HStack(spacing: 12)
                {
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
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .hideFirstRowSeparator(true)
            .tracksContextMenu(suggestedName: { "All Albums" }) { allTracks }

            if !noAlbumTracks.isEmpty
            {
                NavigationLink(value: NoAlbumKey())
                {
                    HStack(spacing: 12)
                    {
                        Image(systemName: "square.dashed")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                        Text("(no album)").italic()
                        Spacer()
                        Text("\(noAlbumTracks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .tracksContextMenu(suggestedName: { "" }) { noAlbumTracks }
            }

            ForEach(albumKeys)
            { key in
                NavigationLink(value: key)
                {
                    AllArtistsAlbumRow(
                        key:                key,
                        trackCount:         trackCount(forAlbumKey: key),
                        representativePath: representativePath(for: key)
                    )
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .tracksContextMenu(suggestedName: { key.album })
                                  { tracks(forAlbumKey: key) }
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .navigationTitle("All Artists")
        .navigationBarTitleDisplayMode(.inline)
        // Local destinations: AlbumKey for individual album rows,
        // AllSongsKey for the All Albums sentinel, NoAlbumKey for
        // the global "(no album)".
        .navigationDestination(for: AlbumKey.self)
        { key in
            AlbumDetailView(key: key)
        }
        .navigationDestination(for: AllSongsKey.self)
        { _ in
            AllSongsView()
        }
        .navigationDestination(for: NoAlbumKey.self)
        { _ in
            NoAlbumGlobalView()
        }
    }

    // Distinct (artist, album) pairs from non-empty-album tracks,
    // sorted by album then artist (matches AlbumsView).
    private var albumKeys: [AlbumKey]
    {
        var seen: Set<AlbumKey> = []
        var ordered: [AlbumKey] = []
        for t in library.tracks where !t.isPodcast
        {
            guard !t.album.isEmpty else { continue }
            let key = AlbumKey(artist: t.artist, album: t.album)
            if seen.insert(key).inserted { ordered.append(key) }
        }
        return ordered.sorted
        { lhs, rhs in
            if lhs.album.localizedCaseInsensitiveCompare(rhs.album) != .orderedSame
            {
                return lhs.album.localizedCaseInsensitiveCompare(rhs.album) == .orderedAscending
            }
            return lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) == .orderedAscending
        }
    }

    private var allTracks: [Track]
    {
        library.tracks.filter { !$0.isPodcast }
    }

    private var noAlbumTracks: [Track]
    {
        library.tracks.filter { !$0.isPodcast && $0.album.isEmpty }
    }

    private func trackCount(forAlbumKey key: AlbumKey) -> Int
    {
        library.tracks.lazy.filter
        { !$0.isPodcast && $0.artist == key.artist && $0.album == key.album }
            .count
    }

    private func tracks(forAlbumKey key: AlbumKey) -> [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.artist == key.artist && $0.album == key.album }
            .sorted
            { lhs, rhs in
                if lhs.trackNumber != rhs.trackNumber
                {
                    return lhs.trackNumber < rhs.trackNumber
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    private func representativePath(for key: AlbumKey) -> String?
    {
        library.tracks.first(where:
        { !$0.isPodcast && $0.artist == key.artist && $0.album == key.album })?
            .filePath
    }
}

// Album row inside AllArtistsView. Shows artwork + album title +
// artist subtitle (since multiple artists may share album titles in
// this aggregate view) + track count.
private struct AllArtistsAlbumRow: View
{
    let key:                AlbumKey
    let trackCount:         Int
    let representativePath: String?

    @State private var artwork: UIImage?

    var body: some View
    {
        HStack(spacing: 12)
        {
            artworkThumb
            VStack(alignment: .leading, spacing: 2)
            {
                Text(key.album).lineLimit(1)
                if !key.artist.isEmpty
                {
                    Text(key.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
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

// MARK: - AllSongsView (All Albums leaf — every music track)

// Reached from any "All Albums" sentinel in the library-browsing
// hierarchy (AllArtistsView, AlbumsView, GenresView). Shows every
// non-podcast track sorted by artist -> album -> track # -> title
// so the list naturally clusters per-artist.
struct AllSongsView: View
{
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
            .filter { !$0.isPodcast }
            .sorted
            { lhs, rhs in
                if lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) != .orderedSame
                {
                    return lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) == .orderedAscending
                }
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

// MARK: - NoAlbumGlobalView ("(no album)" leaf — every track lacking an album tag)

// Reached from any global "(no album)" sentinel. Shows every non-
// podcast track whose album field is empty, regardless of artist,
// sorted by artist -> track # -> title.
struct NoAlbumGlobalView: View
{
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
        .navigationTitle("(no album)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tracks: [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.album.isEmpty }
            .sorted
            { lhs, rhs in
                if lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) != .orderedSame
                {
                    return lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) == .orderedAscending
                }
                if lhs.trackNumber != rhs.trackNumber
                {
                    return lhs.trackNumber < rhs.trackNumber
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }
}
