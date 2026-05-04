import SwiftUI

// Bottom-edge transport strip pinned above the system tab bar (or above the
// safe-area inset on a tabless layout). Hidden when nothing is loaded; shows
// thumbnail + title/artist + play/pause + skip when a track is current.
struct TransportBar: View
{
    @EnvironmentObject var audio: AudioPlayer
    @EnvironmentObject var queue: PlayQueue

    @State private var artwork: UIImage?

    var body: some View
    {
        if let track = audio.currentTrack
        {
            HStack(spacing: 12)
            {
                artworkView
                VStack(alignment: .leading, spacing: 1)
                {
                    Text(track.displayTitle)
                        .font(.body)
                        .lineLimit(1)
                    if !track.subtitle.isEmpty
                    {
                        Text(track.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button { audio.togglePlayPause() }
                label:
                {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Button { audio.playNext() }
                label:
                {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .opacity(queue.canAdvance ? 1.0 : 0.35)
                }
                .buttonStyle(.plain)
                .disabled(!queue.canAdvance)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .top)
            {
                Divider()
            }
            .task(id: track.filePath)
            {
                artwork = await loadArtwork(for: track.filePath)
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View
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
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
