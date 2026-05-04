import SwiftUI

// Full-screen Now Playing surface presented as an overlay (not a system
// sheet) so the parent RootView can drive an expand-from-bar transition
// via matchedGeometryEffect. Caller owns dismissal via the onDismiss
// closure; the close button and drag-down gesture both call it.
struct NowPlayingSheet: View
{
    var onDismiss:             () -> Void      = {}
    var onDragProgressChange:  (CGFloat) -> Void = { _ in }

    @EnvironmentObject var audio: AudioPlayer
    @EnvironmentObject var queue: PlayQueue

    @State private var artwork:         UIImage?
    @State private var sliderValue:     Double = 0
    @State private var userIsScrubbing: Bool   = false

    // Tracks the user's finger during a drag-to-dismiss; auto-resets to 0
    // when the gesture ends (with a spring) so a release-without-dismissal
    // returns the sheet to its full-screen position smoothly.
    @GestureState private var dragOffset: CGFloat = 0

    // Threshold at which a drag-down release commits to dismissal; below
    // that, the sheet snaps back. Same scale used to compute tab fade-in.
    private static let dismissThreshold: CGFloat = 110

    var body: some View
    {
        ZStack(alignment: .topLeading)
        {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

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

            // Close affordance in the top-leading corner. The drag-down
            // gesture below mirrors the sheet's swipe-to-dismiss feel.
            Button
            {
                onDismiss()
            }
            label:
            {
                Image(systemName: "chevron.down")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top,     16)
        }
        .offset(y: max(0, dragOffset))
        .onChange(of: audio.currentTime)
        { newTime in
            if !userIsScrubbing { sliderValue = newTime }
        }
        .onChange(of: audio.currentTrack?.filePath)
        { _ in
            sliderValue = audio.currentTime
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .updating($dragOffset)
                { value, state, transaction in
                    // Only track downward drags. The transaction's spring
                    // animation runs when the gesture ends and @GestureState
                    // resets, so a release-without-dismiss snaps back.
                    state = max(0, value.translation.height)
                    transaction.animation = .spring(response: 0.32,
                                                     dampingFraction: 0.85)
                }
                .onChanged
                { value in
                    let raw      = max(0, value.translation.height)
                    let progress = min(raw / Self.dismissThreshold, 1)
                    onDragProgressChange(progress)
                }
                .onEnded
                { value in
                    if value.translation.height > Self.dismissThreshold
                    {
                        onDismiss()
                    }
                    else
                    {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85))
                        {
                            onDragProgressChange(0)
                        }
                    }
                }
        )
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
                upNext
            }
            .padding(.horizontal, 24)
            .padding(.top,        32)
            .padding(.bottom,     32)
        }
        .task(id: track.filePath)
        {
            artwork = await loadFullArtwork(for: track.filePath)
        }
    }

    @ViewBuilder
    private var upNext: some View
    {
        let upcoming = Array(queue.tracks.dropFirst(queue.currentIndex + 1))
        if !upcoming.isEmpty
        {
            VStack(alignment: .leading, spacing: 8)
            {
                Text("Up Next")
                    .font(.headline)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                // LazyVStack so a 1000-track queue doesn't materialise every
                // upcoming row (and load every artwork) up front when the
                // sheet first appears. Only rows entering the viewport
                // build their views and run their .task.
                LazyVStack(spacing: 0)
                {
                    ForEach(Array(upcoming.enumerated()), id: \.element.id)
                    { (offset, upcomingTrack) in
                        Button
                        {
                            jump(to: queue.currentIndex + 1 + offset)
                        }
                        label:
                        {
                            UpNextRow(track: upcomingTrack)
                        }
                        .buttonStyle(.plain)

                        if offset < upcoming.count - 1
                        {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private func jump(to index: Int)
    {
        if let next = queue.jump(to: index) { audio.play(next) }
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
            CircleSlider(
                value: $sliderValue,
                range: 0 ... max(audio.duration, 1),
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
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 32))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)

            Button { audio.togglePlayPause() }
            label:
            {
                // Fixed frame keeps the surrounding skip / back buttons
                // from shifting horizontally when the icon swaps between
                // play.fill and pause.fill (different glyph widths).
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 56))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)

            Button { audio.playNext() }
            label:
            {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 32))
                    .frame(width: 48, height: 48)
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

// Compact "Up Next" row: smaller thumb + smaller text than the main library
// row; lives inside the Now Playing sheet, not the main lists.
private struct UpNextRow: View
{
    let track: Track

    @State private var artwork: UIImage?

    var body: some View
    {
        HStack(spacing: 12)
        {
            thumb
            VStack(alignment: .leading, spacing: 2)
            {
                Text(track.displayTitle)
                    .font(.subheadline)
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
            Text(track.formattedDuration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .task(id: track.filePath)
        {
            artwork = await loadThumbnail(for: track.filePath)
        }
    }

    @ViewBuilder
    private var thumb: some View
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
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
