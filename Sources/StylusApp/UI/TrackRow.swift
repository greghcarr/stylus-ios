import SwiftUI

// Single-row representation of a track. Loads its own artwork lazily via
// .task on appearance; the ArtworkCache short-circuits if it's already
// decoded. Pure presentation - tap-to-play is in TrackRowButton.
struct TrackRow: View
{
    let track:     Track
    let isPlaying: Bool

    @State private var artwork: UIImage?

    var body: some View
    {
        HStack(spacing: 12)
        {
            artworkThumb
            VStack(alignment: .leading, spacing: 2)
            {
                Text(track.displayTitle)
                    .lineLimit(1)
                if !track.subtitle.isEmpty
                {
                    Text(track.subtitle)
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
            HStack(spacing: 4)
            {
                if isPlaying
                {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                Text(track.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
