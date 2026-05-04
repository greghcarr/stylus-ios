import SwiftUI

struct ArtistsView: View
{
    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List(artistRows, id: \.name)
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
        }
        .listStyle(.plain)
        .navigationTitle("Artists")
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
        for t in library.tracks
        {
            guard !t.artist.isEmpty else { continue }
            counts[t.artist, default: 0] += 1
        }
        return counts.map { ArtistRow(name: $0.key, count: $0.value) }
                     .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private struct ArtistRow
    {
        let name:  String
        let count: Int
    }
}

struct ArtistDetailView: View
{
    let artist: String

    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List(tracks)
        { track in
            TrackRowButton(track: track, visibleTracks: tracks)
        }
        .listStyle(.plain)
        .navigationTitle(artist)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tracks: [Track]
    {
        library.tracks
            .filter { $0.artist == artist }
            .sorted { lhs, rhs in
                if lhs.album != rhs.album
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
