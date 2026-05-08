import SwiftUI

// Single-row representation of a track. Loads its own artwork lazily via
// .task on appearance; the ArtworkCache short-circuits if it's already
// decoded. Pure presentation - tap-to-play is in TrackRowButton.
struct TrackRow: View
{
    let track:     Track
    let isPlaying: Bool
    // When non-nil, replaces the standard track.displayTitle on the
    // first line. SearchView uses this to render tracks as
    // "Artist - Title" so the artist is visible at a glance in a
    // results list that mixes track / artist / album / playlist /
    // podcast hits.
    var titleOverride:    String? = nil
    // When non-nil, replaces the standard "artist - album" subtitle.
    // Used by SearchView to label each result row with the result's
    // type ("Track", "Podcast episode") in place of the usual
    // metadata pair, since the search list mixes types and the type
    // is what the user is scanning for at that moment.
    var subtitleOverride: String? = nil

    @State private var artwork: UIImage?

    var body: some View
    {
        HStack(spacing: 12)
        {
            artworkThumb
            VStack(alignment: .leading, spacing: 2)
            {
                HStack(spacing: 6)
                {
                    Text(titleOverride ?? track.displayTitle)
                        .lineLimit(1)
                    if isPlaying
                    {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                let subtitleText = subtitleOverride ?? track.subtitle
                if !subtitleText.isEmpty
                {
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            trailingMetadata
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .task(id: track.filePath)
        {
            artwork = await loadThumbnail(for: track.filePath)
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
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var trailingMetadata: some View
    {
        VStack(alignment: .trailing, spacing: 2)
        {
            if !analysisLine.isEmpty
            {
                Text(analysisLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(track.formattedDuration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var analysisLine: String
    {
        var parts: [String] = []
        if !track.formattedBpm.isEmpty { parts.append(track.formattedBpm) }
        if !track.key.isEmpty           { parts.append(track.key) }
        return parts.joined(separator: " ")
    }
}
