import SwiftUI

struct SearchView: View
{
    @EnvironmentObject var library: LibraryStore

    @State private var query: String = ""

    var body: some View
    {
        List
        {
            ForEach(matches)
            { track in
                TrackRowButton(track: track, visibleTracks: matches)
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .overlay
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
        }
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
