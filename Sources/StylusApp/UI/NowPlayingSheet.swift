import SwiftUI

// Full-screen Now Playing surface presented as an overlay (not a system
// sheet) so the parent RootView can drive an expand-from-bar transition
// via matchedGeometryEffect. Caller owns dismissal via the onDismiss
// closure; the close button and drag-down gesture both call it.
struct NowPlayingSheet: View
{
    // Shared with RootView. The dismiss-drag gesture inside the
    // sheet writes directly to this so the same value drives both
    // the upward lift drag from the bar and the downward dismiss
    // drag in the sheet -- one source of truth, finger-tracking in
    // both directions. The sheet's vertical .offset is applied by
    // RootView from this binding, NOT here.
    @Binding var sheetY:    CGFloat
    var       onDismiss:    () -> Void = {}

    @EnvironmentObject var audio: AudioPlayer
    @EnvironmentObject var queue: PlayQueue

    @State private var artwork:         UIImage?
    @State private var sliderValue:     Double = 0
    @State private var userIsScrubbing: Bool   = false
    // True while the user is actively gripping the drag handle at
    // the top of the sheet (NOT while they're dragging the artwork
    // region, which uses dismissDrag and leaves this alone). Drives
    // the handle's white-on-grab fill change for a clear "I have it"
    // affordance, matching the mini-player's handle.
    @State private var isHandleGrabbed: Bool   = false

    // Threshold (pt of downward drag from fully-expanded) past which
    // a release commits to dismissal; below it, the sheet snaps
    // back to fully-expanded.
    static let dismissThreshold: CGFloat = 110

    var body: some View
    {
        ZStack(alignment: .top)
        {
            // Match the mini-player TransportBar's frosted gray + its
            // 24 pt top-corner radius. The bar uses
            // .regularMaterial; the closest opaque equivalent for
            // a full-screen sheet is .secondarySystemBackground.
            // Top-corner radii of 24 (matching TransportBar) make
            // the sheet's top edge curve the same way as the bar's
            // when the user drags the sheet down. .ignoresSafeArea
            // extends the rectangle into all safe areas so the
            // sheet still covers the full screen at rest -- the
            // rounded corners sit beneath the status bar / dynamic
            // island when fully expanded, and emerge from behind
            // them as the user drags down.
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading:     24,
                    bottomLeading:   0,
                    bottomTrailing:  0,
                    topTrailing:    24
                ),
                style: .continuous
            )
            .fill(Color(uiColor: .secondarySystemBackground))
            .ignoresSafeArea()

            if let track = audio.currentTrack
            {
                playingView(track)
            }
            else
            {
                VStack
                {
                    dragHandle
                    Spacer()
                    Text("Nothing playing")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        // No .offset(y:) here on purpose: RootView applies the
        // shared sheetY translation. Adding one here would stack on
        // top of the parent's offset and double the drag distance.
        .onChange(of: audio.currentTime)
        { newTime in
            if !userIsScrubbing { sliderValue = newTime }
        }
        .onChange(of: audio.currentTrack?.filePath)
        { _ in
            sliderValue = audio.currentTime
        }
    }

    // Single shared drag gesture used by BOTH the top handle area and
    // the artwork frame so the user can swipe down anywhere above the
    // bottom edge of the album art. Below the artwork we hand the
    // gesture pipeline back to the ScrollView so Up Next can scroll.
    //
    // Coordinate space MUST be .global. The gesture's host view moves
    // down by sheetY via RootView's .offset modifier, so a .local
    // gesture would feed back on itself: as sheetY grows the host's
    // local origin shifts down, which shrinks translation, which
    // shrinks sheetY, which un-shifts the host -- the back-and-forth
    // vertical jitter the user reported earlier. Reading translation
    // in screen coordinates breaks that loop because the finger's
    // absolute position doesn't depend on the view's offset.
    private var dismissDrag: some Gesture
    {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged
            { value in
                // While at fully-expanded rest, downward translation
                // pulls the sheet down. Negative translations would
                // try to push it above the screen top, which we
                // disallow by clamping at 0.
                sheetY = max(0, value.translation.height)
            }
            .onEnded
            { value in
                if value.translation.height > Self.dismissThreshold
                {
                    onDismiss()
                }
                else
                {
                    withAnimation(.spring(response: 0.32,
                                           dampingFraction: 0.85))
                    {
                        sheetY = 0
                    }
                }
            }
    }

    @ViewBuilder
    private var dragHandle: some View
    {
        Capsule()
            .fill(isHandleGrabbed ? Color.white
                                  : Color.secondary.opacity(0.55))
            .frame(width: 44, height: 5)
            // Generous transparent padding so the touch target is
            // ~80 pt tall x most-of-the-screen wide; the visible pill
            // stays small.
            .padding(.vertical, 14)
            .padding(.horizontal, 100)
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .gesture(handleDrag)
            .animation(.easeOut(duration: 0.15), value: isHandleGrabbed)
    }

    // Same shape as dismissDrag but flips isHandleGrabbed on the
    // way in / out so the handle visually responds to the grab.
    // Kept separate from dismissDrag (used by the artwork region)
    // so dragging the artwork doesn't recolour the handle.
    private var handleDrag: some Gesture
    {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged
            { value in
                if !isHandleGrabbed { isHandleGrabbed = true }
                sheetY = max(0, value.translation.height)
            }
            .onEnded
            { value in
                isHandleGrabbed = false
                if value.translation.height > Self.dismissThreshold
                {
                    onDismiss()
                }
                else
                {
                    withAnimation(.spring(response: 0.32,
                                           dampingFraction: 0.85))
                    {
                        sheetY = 0
                    }
                }
            }
    }

    @ViewBuilder
    private func playingView(_ track: Track) -> some View
    {
        VStack(spacing: 0)
        {
            // Non-scrolling top section -- handle + artwork. The drag
            // gesture is attached here so that anywhere above the bottom
            // edge of the album art is a valid swipe-down-to-dismiss
            // region. Pulling artwork OUT of the ScrollView is what lets
            // us own the gesture cleanly: a DragGesture inside a
            // ScrollView competes with scroll and produces the jittery
            // grab-and-shake behaviour the user reported earlier.
            VStack(spacing: 0)
            {
                dragHandle
                artworkView
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
            .gesture(dismissDrag)

            // Everything below the artwork stays in a ScrollView so the
            // Up Next list is scrollable. Title / scrubber / transport
            // are inside the same ScrollView so on smaller screens they
            // can be reached even when Up Next is long.
            ScrollView
            {
                VStack(spacing: 24)
                {
                    titleBlock(track)
                    scrubber
                    transport
                    upNext
                }
                .padding(.horizontal, 24)
                .padding(.top,        24)
                .padding(.bottom,     32)
            }
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
        // Same SilverCircleButtonStyle as the mini-player TransportBar
        // for visual consistency with the app icon and the desktop's
        // transport disc. Larger circle / glyph sizes here because the
        // expanded sheet has the room to feel weighty.
        HStack(spacing: 40)
        {
            Button { audio.playPrev() }
            label:
            {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 26))
            }
            .buttonStyle(SilverCircleButtonStyle(size: 64))

            Button { audio.togglePlayPause() }
            label:
            {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36))
                    // Fixed frame keeps the play / pause glyph from
                    // shifting horizontally inside the silver circle
                    // as the icon name swaps (different glyph widths).
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(SilverCircleButtonStyle(size: 84))

            Button { audio.playNext() }
            label:
            {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 26))
                    .opacity(queue.canAdvance ? 1.0 : 0.35)
            }
            .buttonStyle(SilverCircleButtonStyle(size: 64))
            .disabled(!queue.canAdvance)
        }
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
