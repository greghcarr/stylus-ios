import SwiftUI

// Identifies an album by (artist, album) so two artists with the same album
// title don't collapse into one row, and so an empty-artist track doesn't
// alias into someone else's album.
struct AlbumKey: Hashable, Identifiable
{
    let artist: String
    let album:  String

    var id: String { artist + "\u{1F}" + album }   // unit separator, won't appear in tags
}

struct AlbumsView: View
{
    @EnvironmentObject var library: LibraryStore

    var body: some View
    {
        List
        {
            ForEach(Array(albums.enumerated()), id: \.element.id)
            { (index, key) in
                NavigationLink(value: key)
                {
                    AlbumRow(key: key,
                             representativePath: representativePath(for: key))
                }
                // Pin the row separator's leading edge to the cell's
                // leading edge (same as the Library tab) so it lines
                // up with the album-thumb's left side instead of
                // SwiftUI's default content-derived inset.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(index == 0)
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .tabTitleMenu("Albums")
        .libraryActionsToolbar()
        .navigationDestination(for: AlbumKey.self)
        { key in
            AlbumDetailView(key: key)
        }
        .overlay
        {
            if albums.isEmpty
            {
                EmptyStateView(title: "No albums",
                               systemImage: "square.stack",
                               message: "Tracks will appear here once your library has albums tagged.")
            }
        }
    }

    private var albums: [AlbumKey]
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

    private func representativePath(for key: AlbumKey) -> String?
    {
        library.tracks.first(where: { $0.album == key.album && $0.artist == key.artist })?.filePath
    }
}

private struct AlbumRow: View
{
    let key:                AlbumKey
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

struct AlbumDetailView: View
{
    let key: AlbumKey

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
        .navigationTitle(key.album)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tracks: [Track]
    {
        library.tracks
            .filter { !$0.isPodcast && $0.album == key.album && $0.artist == key.artist }
            .sorted
            { lhs, rhs in
                if lhs.trackNumber != rhs.trackNumber
                {
                    return lhs.trackNumber < rhs.trackNumber
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }
}
