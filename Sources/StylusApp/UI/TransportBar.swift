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

    // Fully dynamic upward swipe support. The bar reports raw
    // translation.height to the parent on every drag sample (negative
    // for upward), and the parent translates that into sheetY so the
    // Now Playing sheet follows the finger in real time. On release,
    // onLiftEnd fires once with the final translation so the parent
    // can decide to snap to expanded or back to the bar.
    var onLiftDrag: (CGFloat) -> Void = { _ in }
    var onLiftEnd:  (CGFloat) -> Void = { _ in }

    @State private var artwork:         UIImage?
    // True while the user is actively gripping the small drag handle
    // at the top of the bar. Drives the handle's white-on-grab fill
    // change so the user gets a clear "I have it" affordance.
    @State private var isHandleGrabbed: Bool    = false

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
        VStack(spacing: 0)
        {
            // Drag handle at the top of the bar. Tapping it presents
            // the Now Playing sheet (same as tapping the info area);
            // dragging it lifts the sheet dynamically (same as
            // dragging the info area). Wrapped in a 24 pt-tall, full-
            // width transparent rectangle so the user has a generous
            // hit area to grab the small visible capsule -- the
            // capsule itself is only 36 x 4 pt, which iOS won't
            // reliably hit-test for finger-sized contacts.
            //
            // .padding(.top, 14) on the visible capsule pushes the
            // capsule down ~half-way into the handle area; the
            // remaining hit area extends 6 pt below the capsule so
            // users grabbing just under it still latch on.
            handleArea

            // Top row: artwork + title / artist. Tappable / swipe-up
            // to open the full Now Playing sheet. The bottom transport
            // row sits below this and keeps its own button hit areas
            // so users can play / pause / skip without expanding.
            // .padding(.top, 20) drops the info row well below the
            // drag handle so it isn't visually pinned to it.
            // .padding(.leading, 12) makes the distance from the
            // album art's left edge to the screen's left edge match
            // the distance from the album art's top edge to the bar's
            // top edge: outer 20 pt + inner 12 pt = 32 pt, which is
            // the same vertical offset (6 capsule top + 4 capsule + 2
            // capsule bottom + 20 info top = 32). Trailing stays
            // unchanged so the row's right side keeps the same outer
            // padding as the transport row below for tab-bar icon
            // alignment.
            // info.top.padding 8 + handle area's 24 pt = 32 pt bar-
            // top-to-album-art-top, matching the album-art-to-screen-
            // left distance (outer 20 + leading 12 = 32). Keeps the
            // square-ish "art bracketed by 32 pt of breathing room"
            // proportion the user asked for.
            //
            // Single info + transport row: artwork + title /
            // artist on the left, play-pause and skip on the right
            // edge of the bar. The info area still owns the tap +
            // swipe-up gestures that present the full Now Playing
            // sheet; the transport buttons handle their own taps
            // separately so the user can play / pause / skip
            // without expanding.
            HStack(spacing: 8)
            {
                nowPlayingInfo(track)
                miniTransportButtons
            }
            .padding(.top, 8)
            .padding(.leading, 12)
        }
        .padding(.horizontal, 20)
        // Small bottom padding shrinks the bar's overall height and
        // brings the artwork close to the home-indicator strip
        // (the bar's frosted material still continues through the
        // safe area below this padding). Top / leading distances
        // around the art remain 32 pt; only the bottom is tightened.
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        // Curve the top corners so the bar visually nests into the
        // iPhone's screen bottom curve. The bar now sits at the very
        // bottom of the screen (system tab bar is above it, home
        // indicator is below), so the material extends through the
        // bottom safe area via .ignoresSafeArea -- otherwise the
        // home-indicator strip would render over a flat colour and
        // the bar would visually float above it.
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
    private var handleArea: some View
    {
        Capsule()
            .fill(isHandleGrabbed ? Color.white
                                  : Color.secondary.opacity(0.55))
            // Matches the big sheet's drag-handle dimensions (88 x 5)
            // so a user transitioning between the mini bar and the
            // expanded sheet sees the same affordance, not two
            // differently-shaped capsules.
            .frame(width: 88, height: 5)
            .padding(.top, 14)
            // Generous transparent hit area so the small capsule is
            // actually grabbable. minHeight 24 + maxWidth .infinity
            // gives the user a bar-wide, ~24 pt tall target; the
            // capsule renders at the top of this area thanks to the
            // alignment, with the rest of the rectangle being
            // invisible-but-tappable.
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .gesture(handleDrag)
            .animation(.easeOut(duration: 0.15), value: isHandleGrabbed)
    }

    private var handleDrag: some Gesture
    {
        // minimumDistance 0 so the moment the user touches the handle
        // we register the grab (and flip isHandleGrabbed so the
        // capsule turns white). location.y in .global coords lets the
        // sheet's top track the finger exactly, same as the info-area
        // lift drag.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged
            { value in
                if !isHandleGrabbed { isHandleGrabbed = true }
                onLiftDrag(value.location.y)
            }
            .onEnded
            { value in
                isHandleGrabbed = false
                onLiftEnd(value.translation.height)
            }
    }

    @ViewBuilder
    private func nowPlayingInfo(_ track: Track) -> some View
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
        // Fully dynamic lift drag. Every sample reports the FINGER'S
        // CURRENT Y in screen coords (value.location.y). The parent
        // sets sheetY so the sheet's top sits exactly under the
        // finger, so there is no constant delta between finger
        // position and sheet position. onEnded reports translation
        // (delta from gesture start) so the parent can apply a fixed
        // distance threshold ("did the user actually drag enough?")
        // independent of where on screen they started.
        //
        // .global coordinate space is required: the bar shifts up as
        // the parent re-renders during the gesture, so a .local
        // reference frame would feed back into the value and
        // produce vertical jitter. minimumDistance 10 trades a
        // smaller initial pop for slightly faster activation; quick
        // taps still go through the wrapping Button untouched.
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .onChanged
                { value in
                    onLiftDrag(value.location.y)
                }
                .onEnded
                { value in
                    onLiftEnd(value.translation.height)
                }
        )
    }

    @ViewBuilder
    private var miniTransportButtons: some View
    {
        // Same SilverCircleButtonStyle as the expanded NowPlaying-
        // Sheet's transport row -- silver gradient + black glyphs
        // matching the app icon and the desktop's transport disc.
        // Sizes are scaled down from the sheet (44 / 36 vs 84 / 64)
        // so the mini bar still reads as compact next to the title
        // text. The skip button's trailing frame edge meets the
        // bar's outer .padding(.horizontal, 20) so it lands ~20 pt
        // from the screen's right edge, matching the artwork's
        // 32 pt distance from the left.
        HStack(spacing: 8)
        {
            // Backward skip mirrors the forward button on the right
            // edge, sitting on the left of the play/pause centrepiece.
            // Always enabled: AudioPlayer.playPrev restarts the
            // current track when there's no previous queue entry, so
            // the button has a meaningful action in every queue state.
            Button { audio.playPrev() }
            label:
            {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(SilverCircleButtonStyle(size: 36))

            Button { audio.togglePlayPause() }
            label:
            {
                // Fixed inner frame keeps the play / pause glyph
                // from shifting horizontally inside the silver
                // circle as the icon name swaps (different glyph
                // widths).
                Image(systemName: audio.isPlaying ? "pause.fill"
                                                  : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(SilverCircleButtonStyle(size: 44))

            Button { audio.playNext() }
            label:
            {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(queue.canAdvance ? 1.0 : 0.35)
            }
            .buttonStyle(SilverCircleButtonStyle(size: 36))
            .disabled(!queue.canAdvance)
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
        // Radial "pie" veil over the artwork. The translucent dark
        // wedge starts at 12 o'clock and sweeps clockwise through
        // the PLAYED portion, so the unveiled part of the artwork
        // is what's still REMAINING. As the track progresses the
        // veiled wedge grows clockwise; at the end the veil covers
        // the whole artwork. Reading audio.currentTime in the body
        // re-renders the bar on each 0.25 s ticker tick, so the
        // veil updates without a separate timer.
        .overlay { playedOverlay }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var playedOverlay: some View
    {
        if audio.currentTrack != nil, audio.duration > 0
        {
            let progress = max(0,
                               min(1,
                                   audio.currentTime / audio.duration))
            PlayedPie(progress: progress)
                .fill(Color.black.opacity(0.7))
        }
    }
}

// Filled wedge that covers the PLAYED portion of a circle,
// sweeping clockwise from 12 o'clock to 12 o'clock + (progress *
// 360°). radius is the rect's diagonal/2 + 1 so the wedge fills
// past the artwork's rounded-rect clipShape and no corner pixels
// are left uncovered as the wedge approaches full.
private struct PlayedPie: Shape
{
    let progress: Double

    func path(in rect: CGRect) -> Path
    {
        var path = Path()
        let p = max(0, min(1, progress))
        // Track just started -- nothing played yet, no veil.
        if p < 0.001 { return path }
        // Track finished -- everything played, full veil (avoids a
        // hairline gap at the seam of a 360° arc).
        if p >= 0.999
        {
            path.addRect(rect)
            return path
        }

        let center  = CGPoint(x: rect.midX, y: rect.midY)
        let r       = (sqrt(rect.width  * rect.width
                          + rect.height * rect.height) / 2) + 1
        let twelve  = -90.0
        let played  = twelve + p * 360
        let rad     = twelve * .pi / 180

        // Center -> 12 o'clock point on the rim -> sweep clockwise
        // through the played portion -> close to center.
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + r * cos(rad),
                                 y: center.y + r * sin(rad)))
        path.addArc(center:     center,
                    radius:     r,
                    startAngle: .degrees(twelve),
                    endAngle:   .degrees(played),
                    clockwise:  false)
        path.closeSubpath()
        return path
    }
}
