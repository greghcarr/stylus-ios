import SwiftUI

// Bottom-edge transport strip pinned above the system tab bar (or above the
// safe-area inset on a tabless layout). Hidden when nothing is loaded; shows
// thumbnail + title/artist + play/pause + skip when a track is current.
//
// Fades in over 0.5 s when a track first loads (when audio.currentTrack
// flips from nil to non-nil). Track-to-track changes don't re-fade since
// the bar stays current throughout.
struct TransportBar: View
{
    @EnvironmentObject var audio: AudioPlayer
    @EnvironmentObject var queue: PlayQueue

    // Caller hooks this to present the full-screen Now Playing sheet.
    var onTap: () -> Void = {}

    @State private var artwork: UIImage?

    var body: some View
    {
        Group
        {
            if let track = audio.currentTrack
            {
                barContent(track)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: audio.currentTrack != nil)
    }

    @ViewBuilder
    private func barContent(_ track: Track) -> some View
    {
        HStack(spacing: 12)
        {
            Button { onTap() }
            label:
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
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                Image(systemName: "forward.end.fill")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .opacity(queue.canAdvance ? 1.0 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!queue.canAdvance)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        // Curve the top corners so the bar visually nests into the
        // iPhone's screen bottom curve. Material extends past the
        // bar's frame into the bottom safe area (where the system tab
        // bar lives) so the two read as a single continuous frosted
        // surface.
        .background(alignment: .top)
        {
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading:     24,
                    bottomLeading:   0,
                    bottomTrailing:  0,
                    topTrailing:    24
                ),
                style: .continuous
            )
            .fill(.regularMaterial)
            .ignoresSafeArea(edges: .bottom)
        }
        .task(id: track.filePath)
        {
            artwork = await loadThumbnail(for: track.filePath)
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
