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
                    HStack
                    {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(row.name)
                        Spacer()
                        Text("\(row.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                // Pin the row separator's leading edge to the cell's
                // leading edge (same as the Library tab) so it lines
                // up with the show icon's left side instead of
                // SwiftUI's default content-derived inset.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(index == 0)
                .tracksContextMenu(suggestedName: { row.name })
                                  { episodes(forShow: row.name) }
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

    private var showRows: [ShowRow]
    {
        var counts: [String: Int] = [:]
        for t in library.tracks where t.isPodcast
        {
            let name = t.podcast.isEmpty ? "Unknown" : t.podcast
            counts[name, default: 0] += 1
        }
        return counts.map { ShowRow(name: $0.key, count: $0.value) }
                     .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        let name:  String
        let count: Int
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
