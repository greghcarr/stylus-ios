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
    @EnvironmentObject        var library: LibraryStore
    @Environment(\.tabRouter) private var router

    var body: some View
    {
        List
        {
            // "All Genres" -- catch-all entry mirroring "All Artists"
            // and "All Albums". Drops the user into a flat every-track
            // view across the library.
            if !allMusicTracks.isEmpty
            {
                Button
                {
                    router?.path.append(AllSongsKey())
                }
                label:
                {
                    LibraryIconRow(icon:  "tag.fill",
                                   title: "All Genres",
                                   count: allMusicTracks.count)
                }
                .buttonStyle(RowTapButtonStyle())
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(true)
                .tracksContextMenu(
                    suggestedName: { "All Genres" },
                    tracksFor:     { allMusicTracks },
                    preview: {
                        LibraryIconRow(icon:  "tag.fill",
                                       title: "All Genres",
                                       count: allMusicTracks.count)
                    }
                )
            }

            // "(no genre)" -- italics flags this as a special category.
            // Hidden when every track has a genre tag.
            if !noGenreTracks.isEmpty
            {
                Button
                {
                    router?.path.append(NoGenreKey())
                }
                label:
                {
                    LibraryDashedRow(title: "(no genre)",
                                   count: noGenreTracks.count)
                }
                .buttonStyle(RowTapButtonStyle())
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .tracksContextMenu(
                    suggestedName: { "" },
                    tracksFor:     { noGenreTracks },
                    preview: {
                        LibraryDashedRow(title: "(no genre)",
                                       count: noGenreTracks.count)
                    }
                )
            }

            ForEach(genreRows, id: \.name)
            { row in
                Button
                {
                    router?.path.append(GenreKey(name: row.name))
                }
                label:
                {
                    CompositeArtworkRow(
                        representativePaths: row.representativePaths,
                        title:               row.name,
                        count:               row.count
                    )
                }
                .buttonStyle(RowTapButtonStyle())
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .tracksContextMenu(
                    suggestedName: { row.name },
                    tracksFor:     { tracks(forGenre: row.name) },
                    preview: {
                        CompositeArtworkRow(
                            representativePaths: row.representativePaths,
                            title:               row.name,
                            count:               row.count
                        )
                    }
                )
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
    //
    // Each row also carries up to 8 representative file paths (one
    // per distinct (artist, album) pair within the genre, sorted
    // alphabetically) feeding the composite artwork thumb.
    private var genreRows: [GenreRow]
    {
        var byGenre: [String: (count: Int, albumToPath: [String: String])] = [:]

        for t in library.tracks where !t.isPodcast
        {
            guard !t.genre.isEmpty else { continue }
            var entry = byGenre[t.genre] ?? (count: 0, albumToPath: [:])
            entry.count += 1
            // Same (artist, album) string can appear under multiple
            // artists with the same album title; key by both so each
            // such combination contributes a separate thumbnail.
            let albumKey = t.artist + "\u{1F}" + t.album
            if entry.albumToPath[albumKey] == nil
            {
                entry.albumToPath[albumKey] = t.filePath
            }
            byGenre[t.genre] = entry
        }

        let rows = byGenre.map
        { (name, info) -> GenreRow in
            let albumKeys = info.albumToPath.keys.sorted()
            let paths = albumKeys.prefix(8).compactMap { info.albumToPath[$0] }
            return GenreRow(name:                name,
                            count:               info.count,
                            representativePaths: Array(paths))
        }
        return rows.sorted
        { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        let name:                String
        let count:               Int
        let representativePaths: [String]
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
