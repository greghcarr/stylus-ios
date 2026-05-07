import SwiftUI

// Identifies a genre by its string name. Wraps the value in its own
// type so the NavigationStack's value-based push is keyed on
// `GenreKey` rather than plain String -- ArtistsView and PodcastsView
// also push String values, so a typed wrapper avoids destination
// ambiguity if more than one of those views is in the stack.
struct GenreKey: Hashable, Identifiable
{
    let name: String

    var id: String { name }
}

struct GenresView: View
{
    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List
        {
            // "All Genres" -- catch-all entry mirroring "All Artists"
            // and "All Albums". Drops the user into a flat every-track
            // view across the library.
            if !allMusicTracks.isEmpty
            {
                NavigationLink(value: AllSongsKey())
                {
                    HStack
                    {
                        Text("All Genres")
                        Spacer()
                        Text("\(allMusicTracks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(true)
                .tracksContextMenu(suggestedName: { "All Genres" })
                                  { allMusicTracks }
            }

            // "(no genre)" -- italics flags this as a special category.
            // Hidden when every track has a genre tag.
            if !noGenreTracks.isEmpty
            {
                NavigationLink(value: NoGenreKey())
                {
                    HStack
                    {
                        Text("(no genre)").italic()
                        Spacer()
                        Text("\(noGenreTracks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .tracksContextMenu(suggestedName: { "" }) { noGenreTracks }
            }

            ForEach(genreRows, id: \.name)
            { row in
                NavigationLink(value: GenreKey(name: row.name))
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
                                  { tracks(forGenre: row.name) }
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .tabTitleMenu("Genres")
        .navigationDestination(for: GenreKey.self)
        { key in
            GenreDetailView(genre: key.name)
        }
        .navigationDestination(for: AllSongsKey.self)
        { _ in
            AllSongsView()
        }
        .navigationDestination(for: NoGenreKey.self)
        { _ in
            NoGenreView()
        }
        .overlay
        {
            if genreRows.isEmpty && noGenreTracks.isEmpty
            {
                EmptyStateView(title: "No genres",
                               systemImage: "tag",
                               message: "Tracks will appear here once your library has genres tagged.")
            }
        }
    }

    private var allMusicTracks: [Track]
    {
        library.tracks.filter { !$0.isPodcast }
    }

    private var noGenreTracks: [Track]
    {
        library.tracks.filter { !$0.isPodcast && $0.genre.isEmpty }
    }

    // Distinct genres present in the music library (podcasts excluded
    // since the desktop scanner doesn't tag genre on podcast files).
    // Empty-genre tracks are skipped rather than bucketed into an
    // "Unknown" row -- consistent with how Artists and Albums omit
    // empty values.
    private var genreRows: [GenreRow]
    {
        var counts: [String: Int] = [:]
        for t in library.tracks where !t.isPodcast
        {
            guard !t.genre.isEmpty else { continue }
            counts[t.genre, default: 0] += 1
        }
        return counts.map { GenreRow(name: $0.key, count: $0.value) }
                     .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Tracks of one genre, ordered the same way GenreDetailView
    // displays them (artist -> album -> trackNumber -> title).
    fileprivate func tracks(forGenre genre: String) -> [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.genre == genre }
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

    private struct GenreRow
    {
        let name:  String
        let count: Int
    }
}

struct GenreDetailView: View
{
    let genre: String

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
        .navigationTitle(genre)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tracks: [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.genre == genre }
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

// "(no genre)" leaf -- every non-podcast track whose genre tag is
// empty, sorted artist -> album -> track # -> title. Reached only
// from the GenresView "(no genre)" sentinel.
struct NoGenreView: View
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
        .navigationTitle("(no genre)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tracks: [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.genre.isEmpty }
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
