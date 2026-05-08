import SwiftUI

struct PodcastsView: View
{
    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List
        {
            ForEach(Array(showRows.enumerated()), id: \.element.name)
            { (index, row) in
                NavigationLink(value: row.name)
                {
                    CompositeArtworkRow(
                        representativePaths: row.representativePaths,
                        title:               row.name,
                        count:               row.count
                    )
                }
                // Pin the row separator's leading edge to the cell's
                // leading edge (same as the Library tab) so it lines
                // up with the artwork-thumb's left side instead of
                // SwiftUI's default content-derived inset.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(index == 0)
                .tracksContextMenu(
                    suggestedName: { row.name },
                    tracksFor:     { episodes(forShow: row.name) },
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
        .tabTitleMenu("Podcasts")
        .libraryActionsToolbar(scope: .podcasts)
        .navigationDestination(for: String.self)
        { show in
            PodcastDetailView(show: show)
        }
        .overlay
        {
            if showRows.isEmpty
            {
                EmptyStateView(title: "No podcasts",
                               systemImage: "mic.slash",
                               message: "Episodes will appear here once your podcasts folder is scanned.")
            }
        }
    }

    // Each show row carries the per-show count plus up to 8
    // representative episode paths -- one per distinct (artist,
    // album) pair within the show, falling back to "first 8
    // episodes" when the show's metadata doesn't tag artist/album.
    // The composite artwork thumb walks these in order, keeping the
    // first 4 successful thumbnail loads.
    private var showRows: [ShowRow]
    {
        var byShow: [String: (count: Int, albumToPath: [String: String])] = [:]

        for t in library.tracks where t.isPodcast
        {
            let name = t.podcast.isEmpty ? "Unknown" : t.podcast
            var entry = byShow[name] ?? (count: 0, albumToPath: [:])
            entry.count += 1
            // For podcasts the (artist, album) pair is often empty
            // or identical for every episode of a show, so fall back
            // to the file path itself as the de-dup key when both
            // tags are missing -- ensures we still surface up to N
            // distinct episode artworks instead of collapsing to a
            // single bucket.
            let pairKey = t.artist + "\u{1F}" + t.album
            let albumKey = (t.artist.isEmpty && t.album.isEmpty)
                ? t.filePath
                : pairKey
            if entry.albumToPath[albumKey] == nil
            {
                entry.albumToPath[albumKey] = t.filePath
            }
            byShow[name] = entry
        }

        let rows = byShow.map
        { (name, info) -> ShowRow in
            let albumKeys = info.albumToPath.keys.sorted()
            let paths = albumKeys.prefix(8).compactMap { info.albumToPath[$0] }
            return ShowRow(name:                name,
                           count:               info.count,
                           representativePaths: Array(paths))
        }
        return rows.sorted
        { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Episodes of one show, ordered the same way PodcastDetailView
    // displays them (highest episode number first, then by title).
    fileprivate func episodes(forShow show: String) -> [Track]
    {
        library.tracks
            .filter
            { $0.isPodcast
              && ($0.podcast == show || ($0.podcast.isEmpty && show == "Unknown")) }
            .sorted
            { lhs, rhs in
                if lhs.trackNumber != rhs.trackNumber
                {
                    return lhs.trackNumber > rhs.trackNumber
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    private struct ShowRow
    {
        let name:                String
        let count:               Int
        let representativePaths: [String]
    }
}

struct PodcastDetailView: View
{
    let show: String

    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List
        {
            ForEach(Array(episodes.enumerated()), id: \.element.id)
            { (index, track) in
                TrackRowButton(track: track, visibleTracks: episodes)
                    .hideFirstRowSeparator(index == 0)
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .navigationTitle(show)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var episodes: [Track]
    {
        library.tracks
            .filter { $0.isPodcast && ($0.podcast == show || ($0.podcast.isEmpty && show == "Unknown")) }
            .sorted
            { lhs, rhs in
                // Higher episode numbers first matches typical podcast app
                // ordering (newest at top); falls back to title for ties.
                if lhs.trackNumber != rhs.trackNumber
                {
                    return lhs.trackNumber > rhs.trackNumber
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }
}
