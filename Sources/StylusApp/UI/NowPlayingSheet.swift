import SwiftUI

// Full-screen sheet presented when the user taps the TransportBar's art /
// title region. Shows large artwork, the track's title block, a seekable
// scrubber, and big transport buttons.
struct NowPlayingSheet: View
{
    @EnvironmentObject var audio: AudioPlayer
    @EnvironmentObject var queue: PlayQueue

    @State private var artwork:         UIImage?
    @State private var sliderValue:     Double = 0
    @State private var userIsScrubbing: Bool   = false

    var body: some View
    {
        Group
        {
            if let track = audio.currentTrack
            {
                playingView(track)
            }
            else
            {
                VStack
                {
                    Spacer()
                    Text("Nothing playing")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onChange(of: audio.currentTime)
        { newTime in
            if !userIsScrubbing { sliderValue = newTime }
        }
        .onChange(of: audio.currentTrack?.filePath)
        { _ in
            sliderValue = audio.currentTime
        }
    }

    @ViewBuilder
    private func playingView(_ track: Track) -> some View
    {
        ScrollView
        {
            VStack(spacing: 24)
            {
                artworkView
                titleBlock(track)
                scrubber
                transport
            }
            .padding(.horizontal, 24)
            .padding(.top,        32)
            .padding(.bottom,     32)
        }
        .task(id: track.filePath)
        {
            artwork = await loadArtwork(for: track.filePath)
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
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
    }

    @ViewBuilder
    private func titleBlock(_ track: Track) -> some View
    {
        VStack(spacing: 4)
        {
            Text(track.displayTitle)
                .font(.title2)
                .bold()
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if !track.subtitle.isEmpty
            {
                Text(track.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var scrubber: some View
    {
        VStack(spacing: 4)
        {
            Slider(
                value: $sliderValue,
                in: 0 ... max(audio.duration, 1),
                onEditingChanged: { editing in
                    userIsScrubbing = editing
                    if !editing { audio.seek(to: sliderValue) }
                }
            )
            HStack
            {
                Text(format(sliderValue))
                Spacer()
                Text(format(audio.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var transport: some View
    {
        HStack(spacing: 40)
        {
            Button { audio.playPrev() }
            label:
            {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)

            Button { audio.togglePlayPause() }
            label:
            {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 56))
            }
            .buttonStyle(.plain)

            Button { audio.playNext() }
            label:
            {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .opacity(queue.canAdvance ? 1.0 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!queue.canAdvance)
        }
        .foregroundStyle(.primary)
        .padding(.top, 8)
    }

    private func format(_ seconds: TimeInterval) -> String
    {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
