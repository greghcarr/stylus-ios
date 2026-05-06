import SwiftUI

struct SearchView: View
{
    @EnvironmentObject var library: LibraryStore

    @State private var query: String = ""

    var body: some View
    {
        // Branch the body instead of using `.overlay` on the List: a
        // List overlay's frame is constrained by the list's section
        // insets, so an "empty state" rendered there ends up offset
        // from the screen's centre. Returning the EmptyStateView at
        // the NavigationStack level lets it fill the full frame and
        // centre horizontally + vertically as intended.
        Group
        {
            if query.isEmpty
            {
                EmptyStateView(title: "Search your library",
                               systemImage: "magnifyingglass",
                               message: "Find tracks by title, artist, or album.")
            }
            else if matches.isEmpty
            {
                EmptyStateView(title: "No results for \"\(query)\"",
                               systemImage: "magnifyingglass")
            }
            else
            {
                List
                {
                    ForEach(Array(matches.enumerated()), id: \.element.id)
                    { (index, track) in
                        TrackRowButton(track: track, visibleTracks: matches)
                            .hideFirstRowSeparator(index == 0)
                    }
                    TransportBarBottomSpacer()
                }
                .listStyle(.plain)
                .listSectionSeparator(.hidden)
            }
        }
        .tabTitleMenu("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
    }

    // Plain case-insensitive substring match across title / artist / album.
    // Cheap enough for ~5 k tracks; anything heavier would warrant indexing.
    private var matches: [Track]
    {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return library.tracks.filter
        { t in
            t.displayTitle.localizedCaseInsensitiveContains(q)
                || t.artist.localizedCaseInsensitiveContains(q)
                || t.album.localizedCaseInsensitiveContains(q)
        }
    }
}
