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
    @EnvironmentObject        var library: LibraryStore
    @Environment(\.tabRouter) private var router

    var body: some View
    {
        List
        {
            // "All Albums" -- mirrors iTunes' top-of-list catch-all.
            // Drops the user into a flat every-track view sorted by
            // artist -> album -> track # -> title. Hidden when the
            // library has no music tracks at all (the empty-state
            // overlay takes over).
            if !allMusicTracks.isEmpty
            {
                Button
                {
                    router?.path.append(AllSongsKey())
                }
                label:
                {
                    LibraryIconRow(icon:  "square.stack.fill",
                                   title: "All Albums",
                                   count: allMusicTracks.count)
                }
                .buttonStyle(RowTapButtonStyle())
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(true)
                .tracksContextMenu(
                    suggestedName: { "All Albums" },
                    tracksFor:     { allMusicTracks },
                    preview: {
                        LibraryIconRow(icon:  "square.stack.fill",
                                       title: "All Albums",
                                       count: allMusicTracks.count)
                    }
                )
            }

            // "(no album)" -- italics flags this as a special
            // category. Hidden when every track has an album tag.
            if !noAlbumTracks.isEmpty
            {
                Button
                {
                    router?.path.append(NoAlbumKey())
                }
                label:
                {
                    LibraryDashedRow(title: "(no album)",
                                   count: noAlbumTracks.count)
                }
                .buttonStyle(RowTapButtonStyle())
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .tracksContextMenu(
                    suggestedName: { "" },
                    tracksFor:     { noAlbumTracks },
                    preview: {
                        LibraryDashedRow(title: "(no album)",
                                       count: noAlbumTracks.count)
                    }
                )
            }

            ForEach(albums, id: \.id)
            { key in
                Button
                {
                    router?.path.append(key)
                }
                label:
                {
                    AlbumRow(key:                key,
                             representativePath: representativePath(for: key),
                             count:              trackCount(for: key))
                }
                .buttonStyle(RowTapButtonStyle())
                // Pin the row separator's leading edge to the cell's
                // leading edge (same as the Library tab) so it lines
                // up with the album-thumb's left side instead of
                // SwiftUI's default content-derived inset.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .tracksContextMenu(
                    suggestedName: { key.album },
                    tracksFor:     { tracks(forAlbum: key) },
                    preview: {
                        AlbumRow(key:                key,
                                 representativePath: representativePath(for: key),
                                 count:              trackCount(for: key))
                    }
                )
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .tabTitleMenu("Albums")
        .navigationDestination(for: AlbumKey.self)
        { key in
            AlbumDetailView(key: key)
        }
        .navigationDestination(for: AllSongsKey.self)
        { _ in
            AllSongsView()
        }
        .navigationDestination(for: NoAlbumKey.self)
        { _ in
            NoAlbumGlobalView()
        }
        .overlay
        {
            if albums.isEmpty && noAlbumTracks.isEmpty
            {
                EmptyStateView(title: "No albums",
                               systemImage: "square.stack",
                               message: "Tracks will appear here once your library has albums tagged.")
            }
        }
    }

    private var allMusicTracks: [Track]
    {
        library.tracks.filter { !$0.isPodcast }
    }

    private var noAlbumTracks: [Track]
    {
        library.tracks.filter { !$0.isPodcast && $0.album.isEmpty }
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

    private func trackCount(for key: AlbumKey) -> Int
    {
        library.tracks.reduce(0)
        { acc, t in
            (!t.isPodcast && t.album == key.album && t.artist == key.artist)
                ? acc + 1
                : acc
        }
    }

    // Tracks of one album, ordered the same way AlbumDetailView
    // displays them (track number then title). Used by the
    // tracksContextMenu so "Play Next" / "Add to Queue" / "Add to
    // Playlist..." on an album row queues the album in playback
    // order.
    fileprivate func tracks(forAlbum key: AlbumKey) -> [Track]
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

private struct AlbumRow: View
{
    let key:                AlbumKey
    let representativePath: String?
    let count:              Int

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
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        // Make the entire row hit-testable so the Button wrapper
        // catches taps in the Spacer area too. See LibraryIconRow
        // for the rationale.
        .contentShape(Rectangle())
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
        .navigationTitle(key.album.isEmpty ? "(no album)" : key.album)
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
