import SwiftUI

// Typed wrappers for value-based navigation specific to search results.
// Plain String pushes would collide with the String-keyed destinations
// registered up the stack by ArtistsView / PodcastsView, and SearchView
// needs to disambiguate "is this an artist or a podcast show?" at
// destination time. AlbumKey / PlaylistKey are already typed and reused.
struct SearchArtistKey:  Hashable { let artist: String }
struct SearchPodcastKey: Hashable { let show:   String }

struct SearchView: View
{
    @State private var query: String = ""

    var body: some View
    {
        // SearchContent is split into its own view so it sits
        // inside the .searchable scope. The query is forwarded as
        // a plain String; the empty-state below renders based
        // solely on whether query is empty.
        SearchContent(query: query)
            .tabTitleMenu("Search")
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always))
            // Local destination registrations so each typed wrapper
            // routes to the matching detail view. AlbumKey is the
            // same type Albums tab uses; PlaylistKey same as Playlists
            // tab. The wrapped String types (artist, podcast show) are
            // SearchView-local to avoid colliding with String pushes
            // up the parent stack.
            .navigationDestination(for: SearchArtistKey.self)
            { key in
                ArtistDetailView(artist: key.artist)
            }
            .navigationDestination(for: AlbumKey.self)
            { key in
                AlbumDetailView(key: key)
            }
            .navigationDestination(for: SearchPodcastKey.self)
            { key in
                PodcastDetailView(show: key.show)
            }
            .navigationDestination(for: PlaylistKey.self)
            { key in
                PlaylistDetailView(playlistId: key.id)
            }
    }
}

// Per-row representation of an artist / album / podcast show / playlist
// search hit. Standard 44 pt composite-thumb leading slot (so all four
// non-track result types feel like the same kind of row), title on
// line 1, type label on line 2.
private struct SearchGroupRow: View
{
    let representativePaths: [String]
    let title:               String
    let typeLabel:           String

    var body: some View
    {
        HStack(spacing: 12)
        {
            CompositeArtworkThumb(representativePaths: representativePaths)
            VStack(alignment: .leading, spacing: 2)
            {
                Text(title).lineLimit(1)
                Text(typeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        // Make the entire row hit-testable so the Button wrapper
        // catches taps in the Spacer area too.
        .contentShape(Rectangle())
    }
}

private struct SearchContent: View
{
    let query: String

    @Environment(\.tabRouter) private var router
    @EnvironmentObject var library:   LibraryStore
    @EnvironmentObject var playlists: PlaylistStore

    var body: some View
    {
        let r = computeResults()
        Group
        {
            if r.isEmpty
            {
                emptyState
            }
            else
            {
                resultsList(r)
            }
        }
    }

    // Two-way empty state:
    //  - query empty (keyboard up or down) -> "Search your library"
    //    prompt fills the space between the search bar at the top
    //    and the keyboard / mini transport bar at the bottom, so
    //    the surface doesn't look unfinished while the user has
    //    just focused the field but hasn't typed yet.
    //  - query non-empty with no matches -> "No results for ..."
    @ViewBuilder
    private var emptyState: some View
    {
        if query.isEmpty
        {
            EmptyStateView(
                title:       "Search your library",
                systemImage: "magnifyingglass",
                message:     "Find tracks, artists, albums, podcasts, episodes, and playlists."
            )
        }
        else
        {
            EmptyStateView(title:       "No results for \"\(query)\"",
                           systemImage: "magnifyingglass")
        }
    }

    @ViewBuilder
    private func resultsList(_ r: SearchResults) -> some View
    {
        // Sections are rendered in the same fixed order regardless of
        // which categories actually have hits, so the user's eye lands
        // on the same place across queries: tracks first (most common
        // intent), then group surfaces, then podcasts, then playlists.
        List
        {
            if !r.tracks.isEmpty
            {
                Section("Tracks")
                {
                    ForEach(r.tracks, id: \.id)
                    { track in
                        TrackRowButton(track:            track,
                                       visibleTracks:    r.tracks,
                                       titleOverride:    formattedTrackTitle(track),
                                       subtitleOverride: "Track")
                    }
                }
            }

            if !r.artists.isEmpty
            {
                Section("Artists")
                {
                    ForEach(r.artists, id: \.name)
                    { hit in
                        Button
                        {
                            router?.path.append(SearchArtistKey(artist: hit.name))
                        }
                        label:
                        {
                            SearchGroupRow(
                                representativePaths: hit.representativePaths,
                                title:               hit.name,
                                typeLabel:           "Artist"
                            )
                        }
                        .buttonStyle(RowTapButtonStyle())
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                }
            }

            if !r.albums.isEmpty
            {
                Section("Albums")
                {
                    ForEach(r.albums, id: \.key.id)
                    { hit in
                        Button
                        {
                            router?.path.append(hit.key)
                        }
                        label:
                        {
                            SearchGroupRow(
                                representativePaths: hit.representativePaths,
                                title:               hit.key.album,
                                typeLabel:           "Album"
                            )
                        }
                        .buttonStyle(RowTapButtonStyle())
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                }
            }

            if !r.podcasts.isEmpty
            {
                Section("Podcasts")
                {
                    ForEach(r.podcasts, id: \.name)
                    { hit in
                        Button
                        {
                            router?.path.append(SearchPodcastKey(show: hit.name))
                        }
                        label:
                        {
                            SearchGroupRow(
                                representativePaths: hit.representativePaths,
                                title:               hit.name,
                                typeLabel:           "Podcast"
                            )
                        }
                        .buttonStyle(RowTapButtonStyle())
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                }
            }

            if !r.episodes.isEmpty
            {
                Section("Podcast Episodes")
                {
                    ForEach(r.episodes, id: \.id)
                    { episode in
                        TrackRowButton(track:            episode,
                                       visibleTracks:    r.episodes,
                                       subtitleOverride: "Podcast episode")
                    }
                }
            }

            if !r.playlists.isEmpty
            {
                Section("Playlists")
                {
                    ForEach(r.playlists, id: \.playlist.id)
                    { hit in
                        Button
                        {
                            router?.path.append(PlaylistKey(id: hit.playlist.id))
                        }
                        label:
                        {
                            SearchGroupRow(
                                representativePaths: hit.representativePaths,
                                title:               hit.playlist.name,
                                typeLabel:           "Playlist"
                            )
                        }
                        .buttonStyle(RowTapButtonStyle())
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                }
            }

            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
    }

    // "Artist - Title" for the track row's first line. Falls back to
    // bare displayTitle when the artist tag is empty (an "Unknown -
    // Title" line would just add noise). Plain ASCII hyphen, never an
    // em / en dash, per project convention.
    private func formattedTrackTitle(_ t: Track) -> String
    {
        t.artist.isEmpty
            ? t.displayTitle
            : "\(t.artist) - \(t.displayTitle)"
    }

    // MARK: - Result computation

    private func computeResults() -> SearchResults
    {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SearchResults() }

        var tracks:   [Track]            = []
        var episodes: [Track]            = []
        var artistsByName: [String: ArtistHit]    = [:]
        var albumsByKey:   [AlbumKey: AlbumHit]   = [:]
        var podcastsByName: [String: PodcastHit]  = [:]

        // Single pass over library.tracks builds every track / episode
        // hit AND collects the per-artist / per-album / per-podcast
        // representative paths used by the composite thumbs. Avoids
        // re-walking the (potentially 5k+) track list once per category.
        for t in library.tracks
        {
            let matchesTrack = t.displayTitle.localizedCaseInsensitiveContains(q)
                || t.artist.localizedCaseInsensitiveContains(q)
                || t.album.localizedCaseInsensitiveContains(q)

            if t.isPodcast
            {
                let matchesEpisode = matchesTrack
                    || t.podcast.localizedCaseInsensitiveContains(q)
                if matchesEpisode { episodes.append(t) }

                // Group-row hit: podcast show name match.
                let show = t.podcast
                if !show.isEmpty,
                   show.localizedCaseInsensitiveContains(q)
                {
                    var hit = podcastsByName[show]
                        ?? PodcastHit(name: show, representativePaths: [])
                    if hit.representativePaths.count < 8
                    {
                        hit.representativePaths.append(t.filePath)
                    }
                    podcastsByName[show] = hit
                }
            }
            else
            {
                if matchesTrack { tracks.append(t) }

                // Group-row hits: artist by name, album by name.
                if !t.artist.isEmpty,
                   t.artist.localizedCaseInsensitiveContains(q)
                {
                    var hit = artistsByName[t.artist]
                        ?? ArtistHit(name: t.artist,
                                     seenAlbumKeys: [],
                                     representativePaths: [])
                    let albumKey = t.artist + "\u{1F}" + t.album
                    if hit.representativePaths.count < 8,
                       hit.seenAlbumKeys.insert(albumKey).inserted
                    {
                        hit.representativePaths.append(t.filePath)
                    }
                    artistsByName[t.artist] = hit
                }

                if !t.album.isEmpty,
                   t.album.localizedCaseInsensitiveContains(q)
                {
                    let key = AlbumKey(artist: t.artist, album: t.album)
                    if albumsByKey[key] == nil
                    {
                        // One representative path per album row is enough
                        // (the row renders a single 44 pt thumbnail, not
                        // a 2x2 composite). We grab the first track we
                        // see for each (artist, album) and stop.
                        albumsByKey[key] = AlbumHit(key:                 key,
                                                    representativePaths: [t.filePath])
                    }
                }
            }
        }

        let sortedArtists = artistsByName.values.sorted
        { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let sortedAlbums = albumsByKey.values.sorted
        { lhs, rhs in
            if lhs.key.album.localizedCaseInsensitiveCompare(rhs.key.album) != .orderedSame
            {
                return lhs.key.album.localizedCaseInsensitiveCompare(rhs.key.album) == .orderedAscending
            }
            return lhs.key.artist.localizedCaseInsensitiveCompare(rhs.key.artist) == .orderedAscending
        }
        let sortedPodcasts = podcastsByName.values.sorted
        { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Playlists: name match. The composite thumb for each match
        // pulls one representative path per distinct (artist, album)
        // pair within the playlist (capped at 8) so the 2x2 composite
        // tells the user "this playlist contains tracks from N albums".
        let libraryByPath = Dictionary(uniqueKeysWithValues:
            library.tracks.map { ($0.filePath, $0) })
        var playlistHits: [PlaylistHit] = []
        for p in playlists.playlists
            where p.name.localizedCaseInsensitiveContains(q)
        {
            var seen: Set<String> = []
            var paths: [String]   = []
            for path in p.trackPaths
            {
                guard let track = libraryByPath[path] else { continue }
                let albumKey = track.artist + "\u{1F}" + track.album
                if seen.insert(albumKey).inserted
                {
                    paths.append(track.filePath)
                    if paths.count >= 8 { break }
                }
            }
            playlistHits.append(PlaylistHit(playlist:            p,
                                            representativePaths: paths))
        }
        playlistHits.sort
        { $0.playlist.name.localizedCaseInsensitiveCompare($1.playlist.name) == .orderedAscending }

        return SearchResults(tracks:    tracks,
                             artists:   sortedArtists,
                             albums:    sortedAlbums,
                             podcasts:  sortedPodcasts,
                             episodes:  episodes,
                             playlists: playlistHits)
    }
}

// MARK: - Result types

private struct SearchResults
{
    var tracks:    [Track]        = []
    var artists:   [ArtistHit]    = []
    var albums:    [AlbumHit]     = []
    var podcasts:  [PodcastHit]   = []
    var episodes:  [Track]        = []
    var playlists: [PlaylistHit]  = []

    var isEmpty: Bool
    {
        tracks.isEmpty && artists.isEmpty && albums.isEmpty
            && podcasts.isEmpty && episodes.isEmpty && playlists.isEmpty
    }
}

private struct ArtistHit
{
    let name:                String
    var seenAlbumKeys:       Set<String>
    var representativePaths: [String]
}

private struct AlbumHit
{
    let key:                 AlbumKey
    let representativePaths: [String]
}

private struct PodcastHit
{
    let name:                String
    var representativePaths: [String]
}

private struct PlaylistHit
{
    let playlist:            Playlist
    let representativePaths: [String]
}
