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
            ForEach(Array(genreRows.enumerated()), id: \.element.name)
            { (index, row) in
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
                .hideFirstRowSeparator(index == 0)
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .tabTitleMenu("Genres")
        .libraryActionsToolbar()
        .navigationDestination(for: GenreKey.self)
        { key in
            GenreDetailView(genre: key.name)
        }
        .overlay
        {
            if genreRows.isEmpty
            {
                EmptyStateView(title: "No genres",
                               systemImage: "tag",
                               message: "Tracks will appear here once your library has genres tagged.")
            }
        }
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
