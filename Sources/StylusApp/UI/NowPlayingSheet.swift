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
    // Top-most sheetY value (sheet's fully-expanded position).
    // Drag handlers clamp here so the user can't pull the sheet
    // higher than its expanded position. RootView passes this
    // explicitly so both views agree on where "fully expanded" is.
    var       minSheetY:    CGFloat   = 0
    var       onDismiss:    () -> Void = {}

    @EnvironmentObject var audio:   AudioPlayer
    @EnvironmentObject var queue:   PlayQueue
    @EnvironmentObject var library: LibraryStore

    @State private var artwork:         UIImage?
    @State private var sliderValue:     Double = 0
    @State private var userIsScrubbing: Bool   = false
    // Suggested Tracks section state. Up to 5 tracks from the
    // library that share artist or genre with the current queue.
    // Replenished on tap-to-add and swipe-to-pass; passes are
    // session-scoped (not persisted).
    @State private var suggestedTracks:  [Track]      = []
    @State private var passedTrackPaths: Set<String>  = []
    // True while the user is actively gripping the drag handle at
    // the top of the sheet (NOT while they're dragging the artwork
    // region, which uses dismissDrag and leaves this alone). Drives
    // the handle's white-on-grab fill change for a clear "I have it"
    // affordance, matching the mini-player's handle.
    @State private var isHandleGrabbed: Bool   = false
    // ScrollView's current vertical scroll offset. Drives the
    // collapsing artwork at the top of the scroll content: the
    // artwork shrinks from full size to artworkMinScale over the
    // first `collapseRange` pt of upward scroll while staying
    // pinned at the visible top, then -- once fully collapsed --
    // moves up off-screen with continued scrolling like a normal
    // scroll-view item. Tracked via a PreferenceKey on the
    // scroll content's background; see playingView below.
    @State private var scrollOffset:    CGFloat = 0

    // Threshold (pt of downward drag from fully-expanded) past which
    // a release commits to dismissal; below it, the sheet snaps
    // back to fully-expanded.
    static let dismissThreshold: CGFloat = 110

    // Artwork sizing for the collapsing-header effect.
    private static let artworkFullSize: CGFloat = 320
    private static let artworkMinScale: CGFloat = 0.25
    private static var collapseRange:   CGFloat
    {
        artworkFullSize * (1 - artworkMinScale)
    }

    private var artworkScale: CGFloat
    {
        let progress = max(0,
                           min(1, scrollOffset / Self.collapseRange))
        return 1 - progress * (1 - Self.artworkMinScale)
    }

    // While the user is in the collapse-range portion of the scroll,
    // counter-translate the artwork by exactly the scroll amount so
    // its top stays pinned to the visible top of the scroll area --
    // it shrinks IN PLACE rather than scrolling up under the title.
    // After the collapse range, freeze the counter-translate so the
    // (now small) artwork moves up with continued scrolling like any
    // other scroll-view item.
    private var artworkStickyOffset: CGFloat
    {
        min(scrollOffset, Self.collapseRange)
    }

    var body: some View
    {
        ZStack(alignment: .top)
        {
            // Match the mini-player TransportBar's frosted gray + its
            // 24 pt top-corner radius. The bar uses
            // .regularMaterial; the closest opaque equivalent for
            // a full-screen sheet is .secondarySystemBackground.
            // .ignoresSafeArea(edges: .bottom) only -- the sheet's
            // top edge stays at the top safe-area inset (just below
            // the status bar / dynamic island), so the black
            // backdrop RootView paints behind the sheet shows
            // through above. Visually: rounded card on a black
            // backdrop, with the system status bar rendering over
            // the black instead of over the sheet's gray.
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
            .ignoresSafeArea(edges: .bottom)

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
        { _, newTime in
            if !userIsScrubbing { sliderValue = newTime }
        }
        .onChange(of: audio.currentTrack?.filePath)
        {
            sliderValue = audio.currentTime
        }
        // Seed sliderValue on first mount. The two .onChange handlers
        // above only fire when their observed value CHANGES, but on
        // auto-present (scenePhase = .active after returning from
        // another audio app, etc.) the sheet mounts cold while the
        // track is paused at some non-zero offset. Without this
        // seed, sliderValue stays at its initial 0 until the next
        // tick of the AudioPlayer timer -- which doesn't tick while
        // paused -- so the seek bar shows 0:00 even though the
        // underlying audio.currentTime is correct. Hitting play
        // would then snap the bar from 0:00 to the real position
        // a moment later. .task fires every time the sheet mounts,
        // so this also handles the dismiss/re-present cycle.
        .task
        {
            sliderValue = audio.currentTime
            recomputeSuggestions()
        }
        // Re-rank the Suggested Tracks list whenever the playback
        // context changes. Watching currentTrack.filePath catches
        // skip / advance / row-tap; watching queue.tracks.count
        // catches "Add to Queue" from elsewhere in the app without
        // a track change. Both triggers do a full recompute, which
        // also drops any passes that no longer apply (the same
        // candidate pool reseeds the section).
        .onChange(of: audio.currentTrack?.filePath)
        {
            recomputeSuggestions()
        }
        .onChange(of: queue.tracks.count)
        {
            recomputeSuggestions()
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
                // The sheet starts the drag at its fully-expanded
                // position (sheetY = minSheetY). Add the drag's
                // downward translation to that. Negative translations
                // would try to push it above its expanded position,
                // which we disallow by clamping at minSheetY.
                sheetY = max(minSheetY,
                             minSheetY + value.translation.height)
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
                        sheetY = minSheetY
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
            .frame(width: 88, height: 5)
            // Expand to the full sheet width so the tap area covers
            // the entire region above the album art, not just a
            // narrow strip around the visible capsule. Tap-to-
            // dismiss feels consistent with the dim-overlay tap and
            // with the user's expectation that "anywhere above the
            // art" dismisses.
            .frame(maxWidth: .infinity)
            // Symmetric vertical padding so the gap from the sheet's
            // top edge to the capsule's top equals the gap from the
            // capsule's bottom to the album art's top. The extent
            // of this padding (and therefore the position of the
            // album art) is fixed; we deliberately don't try to
            // center the artwork on screen.
            .padding(.vertical, 22)
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
                sheetY = max(minSheetY,
                             minSheetY + value.translation.height)
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
                        sheetY = minSheetY
                    }
                }
            }
    }

    @ViewBuilder
    private func playingView(_ track: Track) -> some View
    {
        VStack(spacing: 0)
        {
            // Drag handle stays sticky above the ScrollView so the
            // user can always grab it for a downward dismiss, even
            // when they've scrolled the queue.
            dragHandle

            // Single ScrollView holds the artwork + title + scrubber
            // + transport + Up Next. Dragging the artwork upward
            // scrolls the queue into view; dragging it downward at
            // scroll-top dismisses the sheet (downward drags mid-
            // scroll fall through to the ScrollView's normal scroll
            // behaviour).
            ScrollViewReader
            { scrollProxy in
                ScrollView
                {
                    VStack(spacing: 0)
                    {
                        artworkView
                            // Tagged so onAppear's scrollProxy can
                            // jump us back here when the sheet is
                            // re-presented (e.g. user taps the
                            // mini-bar again, or returns to the app
                            // via the dynamic island and RootView
                            // auto-presents).
                            .id("npTop")
                            .frame(width:  Self.artworkFullSize,
                                   height: Self.artworkFullSize)
                            // Centre the (potentially-shrunken) artwork
                            // horizontally within the available width.
                            .frame(maxWidth: .infinity,
                                   alignment: .center)
                            // anchor: .top means the artwork's top
                            // edge stays put as it shrinks; the
                            // bottom rises toward it. Combined with
                            // the sticky offset below, this keeps
                            // the artwork pinned at the visible top
                            // of the scroll while it shrinks from
                            // full size to artworkMinScale.
                            .scaleEffect(artworkScale, anchor: .top)
                            .offset(y: artworkStickyOffset)
                            // No gesture on the artwork: even a
                            // simultaneousGesture with a downward-
                            // and-scroll-top-only filter blocks
                            // the ScrollView from receiving upward
                            // drags as scroll input. Dismiss-by-
                            // pulling-art-down would need a UIKit
                            // UIPanGestureRecognizer (via
                            // UIViewRepresentable) that fails
                            // itself for upward drags so ScrollView
                            // can take over -- a future change.
                            // For now the drag handle owns the
                            // downward dismiss.

                        VStack(spacing: 24)
                        {
                            titleBlock(track)
                            scrubber
                            transport
                            upNext
                            suggestedTracksSection(scrollProxy: scrollProxy)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top,        24)
                        .padding(.bottom,     32)

                        // Sentinel at the very end of the scroll
                        // content so .scrollTo("scrollBottom",
                        // anchor: .bottom) lands the user at the true
                        // content bottom -- including the 32 pt
                        // bottom padding above. Scrolling to the last
                        // suggestion row directly leaves that padding
                        // below the viewport, which read as "the
                        // scroll didn't go far enough" and produced
                        // a constant offset on every subsequent
                        // scroll-on-add.
                        Color.clear
                            .frame(height: 1)
                            .id("scrollBottom")
                    }
                }
                // iOS 18+ scroll-geometry tracking. The
                // GeometryReader-in-background trick that's
                // standard on iOS 16/17 didn't fire reliably on
                // this device; this API reports contentOffset
                // directly. contentOffset.y is 0 at scroll-top and
                // grows positive as the user scrolls up.
                .onScrollGeometryChange(for: CGFloat.self)
                { proxy in
                    proxy.contentOffset.y
                }
                action:
                { _, newValue in
                    scrollOffset = max(0, newValue)
                }
                // Reset the scroll position when the sheet is
                // presented. NowPlayingSheet is conditionally
                // rendered by RootView, so .onAppear fires every
                // time the sheet mounts (tap, swipe-up, or
                // RootView's scenePhase auto-present on return
                // from background -- the dynamic-island re-entry
                // case the user wanted handled).
                .onAppear
                {
                    scrollProxy.scrollTo("npTop", anchor: .top)
                }
            }
        }
        .task(id: track.filePath)
        {
            artwork = await loadFullArtwork(for: track.filePath)
        }
    }

    // Downward-drag dismiss on the artwork. Only fires when scroll
    // is at the top so that dragging-down mid-scroll falls through
    // to ScrollView's natural scroll-up behaviour. .global coord
    // space matches the rest of the dismiss gestures in this view.
    // .simultaneous (not .gesture / .highPriority) lets ScrollView
    // still receive UPWARD drags as scroll input; we only inspect
    // and react.
    private var artworkDismissDrag: some Gesture
    {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged
            { value in
                if value.translation.height > 0 && scrollOffset <= 1
                {
                    sheetY = minSheetY + value.translation.height
                }
            }
            .onEnded
            { value in
                let dragged = value.translation.height
                if dragged > Self.dismissThreshold && scrollOffset <= 1
                {
                    onDismiss()
                }
                else if sheetY > minSheetY
                {
                    withAnimation(.spring(response: 0.32,
                                           dampingFraction: 0.85))
                    {
                        sheetY = minSheetY
                    }
                }
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

    // MARK: - Suggested Tracks

    private static let suggestionCount = 5

    @ViewBuilder
    private func suggestedTracksSection(
        scrollProxy: ScrollViewProxy
    ) -> some View
    {
        if !suggestedTracks.isEmpty
        {
            VStack(alignment: .leading, spacing: 8)
            {
                Text("Suggested Tracks")
                    .font(.headline)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                LazyVStack(spacing: 0)
                {
                    ForEach(Array(suggestedTracks.enumerated()), id: \.element.id)
                    { (offset, track) in
                        SuggestedTrackRow(
                            track:  track,
                            onAdd:
                            {
                                addSuggestionToQueue(track)
                                // Up Next just grew by one row, which
                                // pushes Suggested Tracks down inside
                                // the scroll content. Scroll to the
                                // sentinel at the very bottom of the
                                // scroll content so the user stays
                                // anchored to the bottom of the sheet.
                                //
                                // Delayed deliberately so the cross-
                                // fade has visibly started before the
                                // scroll begins. Running both on the
                                // same runloop made the scroll move
                                // content upward simultaneously with
                                // the fade, which read as the list
                                // "competing with the Suggested
                                // Tracks header" -- rows passing
                                // through the header's vertical space
                                // mid-fade.
                                DispatchQueue.main
                                    .asyncAfter(deadline: .now() + 0.18)
                                {
                                    withAnimation(
                                        .easeInOut(duration: 0.4)
                                    )
                                    {
                                        scrollProxy.scrollTo(
                                            "scrollBottom",
                                            anchor: .bottom
                                        )
                                    }
                                }
                            },
                            onPass: { passSuggestion(track) }
                        )
                        // Opacity-only transition so the inserted row
                        // doesn't briefly take an extra layout slot
                        // while the outgoing row is still in place.
                        .transition(.opacity)

                        if offset < suggestedTracks.count - 1
                        {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                // One animation modifier for the whole list. Any
                // mutation of suggestedTracks (local splice from "+",
                // pass, or .onChange recompute) animates uniformly
                // as a single transaction, so rows shift in lock-
                // step instead of segmenting across multiple
                // implicit / explicit animation boundaries. 0.4 s
                // gives the cross-fade enough room to read as a
                // deliberate transition rather than a flicker.
                .animation(.easeInOut(duration: 0.4),
                           value: suggestedTracks)
            }
        }
    }

    // Pool of library music tracks not in the queue, not already
    // suggested, and not previously passed in this session.
    private func candidatePool(excluding extra: Set<String> = []) -> [Track]
    {
        let queuePaths    = Set(queue.tracks.map(\.filePath))
        let suggestedSet  = Set(suggestedTracks.map(\.filePath))
        let exclude       = queuePaths
            .union(passedTrackPaths)
            .union(suggestedSet)
            .union(extra)

        let contextArtists = Set(queue.tracks
            .map(\.artist).filter { !$0.isEmpty })
        let contextGenres  = Set(queue.tracks
            .map(\.genre ).filter { !$0.isEmpty })

        return library.tracks.filter
        { t in
            !t.isPodcast
         && !exclude.contains(t.filePath)
         && (contextArtists.contains(t.artist)
          || contextGenres .contains(t.genre))
        }
    }

    // Score: 2 for artist match, 1 for genre match. Used to bucket
    // candidates into score tiers; tracks within a tier are
    // randomised so the same five don't always surface.
    private func similarityScore(_ track: Track) -> Int
    {
        let contextArtists = Set(queue.tracks
            .map(\.artist).filter { !$0.isEmpty })
        let contextGenres  = Set(queue.tracks
            .map(\.genre ).filter { !$0.isEmpty })

        var s = 0
        if contextArtists.contains(track.artist) { s += 2 }
        if contextGenres .contains(track.genre)  { s += 1 }
        return s
    }

    // Library music tracks not in the queue, not passed this
    // session, not already suggested. Used as a fallback when the
    // context-filtered candidate pool is empty -- e.g. queue is
    // empty (no context to match), or the queue's artists / genres
    // don't overlap with anything else in the library. These
    // tracks have similarityScore 0, so they only surface when the
    // context pool can't fill a slot.
    private func randomFallbackPool() -> [Track]
    {
        let queuePaths   = Set(queue.tracks.map(\.filePath))
        let suggestedSet = Set(suggestedTracks.map(\.filePath))
        let exclude      = queuePaths
            .union(passedTrackPaths)
            .union(suggestedSet)

        return library.tracks.filter
        { t in
            !t.isPodcast && !exclude.contains(t.filePath)
        }
    }

    // Refresh the suggestion list. Preserves existing entries that
    // are still eligible -- only DROPS entries that have left the
    // pool (added to queue, passed, or no longer in library) and
    // FILLS empty slots from the candidate pool (or random fallback
    // when the context pool is empty). Idempotent: running twice in
    // a row is a no-op, so the local-splice path and the .onChange
    // path can both call this without stomping each other or
    // reshuffling the user's visible list on every action.
    private func recomputeSuggestions()
    {
        let queuePaths   = Set(queue.tracks.map(\.filePath))
        let libraryPaths = Set(library.tracks.map(\.filePath))

        // Compute the still-eligible subset and only assign back to
        // @State if it actually differs. removeAll(where:) on the
        // existing array would mark @State dirty even when no
        // elements match the predicate, kicking off a re-render
        // (and a stray animation when .animation(_:value:) is
        // attached). This keeps idempotent recompute calls truly
        // free.
        let stillEligible = suggestedTracks.filter
        { t in
            !queuePaths.contains(t.filePath)
         && !passedTrackPaths.contains(t.filePath)
         &&  libraryPaths.contains(t.filePath)
        }
        if stillEligible != suggestedTracks
        {
            suggestedTracks = stillEligible
        }

        while suggestedTracks.count < Self.suggestionCount
        {
            let beforeCount = suggestedTracks.count
            drawReplacement()
            // Both pools exhausted; drawReplacement is a no-op.
            // Break to avoid spinning forever.
            if suggestedTracks.count == beforeCount { break }
        }
    }

    // Pick one fresh track to slot into the suggestions: highest-
    // scoring candidate first, falling back to random library music
    // when the context pool is empty. Excludes everything already
    // in the queue / passed / currently-suggested via candidatePool's
    // built-in filtering.
    private func pickNextSuggestion() -> Track?
    {
        var pool = candidatePool()
        if pool.isEmpty { pool = randomFallbackPool() }
        guard !pool.isEmpty else { return nil }

        let topScore  = pool.map(similarityScore).max() ?? 0
        let topBucket = pool.filter { similarityScore($0) == topScore }
        return topBucket.randomElement()
    }

    // Append a fresh suggestion to the end of the list. Used by
    // recomputeSuggestions to fill empty slots after entries have
    // been dropped (e.g. on track change when the previous context
    // shifted).
    private func drawReplacement()
    {
        if let next = pickNextSuggestion() { suggestedTracks.append(next) }
    }

    // Swap a tapped suggestion for a fresh draw at the SAME index,
    // so the row's slot stays put and the content cross-fades in
    // place rather than the row sliding out and a new one appearing
    // at the bottom. If the pool is exhausted, just drop the row
    // (the list shrinks below 5; the section hides at 0).
    private func replaceSuggestion(at track: Track)
    {
        guard let idx = suggestedTracks.firstIndex(
            where: { $0.filePath == track.filePath }
        )
        else { return }

        if let next = pickNextSuggestion()
        {
            suggestedTracks[idx] = next
        }
        else
        {
            suggestedTracks.remove(at: idx)
        }
    }

    private func addSuggestionToQueue(_ track: Track)
    {
        // Plain mutations -- the LazyVStack's
        // .animation(_:value: suggestedTracks) modifier picks up the
        // change and cross-fades the row in place. Wrapping in
        // withAnimation here would spawn a competing animation
        // transaction, which read as "segmented" row movement.
        queue.append([track])
        replaceSuggestion(at: track)
    }

    private func passSuggestion(_ track: Track)
    {
        passedTrackPaths.insert(track.filePath)
        replaceSuggestion(at: track)
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
        // Five-button layout mirroring the desktop's transport row:
        // shuffle | prev | play | next | repeat. Shuffle / repeat are
        // smaller un-disced glyphs (matches the desktop's modBtnD = 28
        // mod-button styling) tinted accent when active so the silver
        // discs of the three real transport buttons stay the visual
        // anchor of the row. Spacers expand to balance the row across
        // the available width on iPhone SE through Pro Max.
        HStack(spacing: 0)
        {
            shuffleToggle
            Spacer(minLength: 12)

            Button { audio.playPrev() }
            label:
            {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 26))
            }
            .buttonStyle(SilverCircleButtonStyle(size: 64))

            Spacer(minLength: 16)

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

            Spacer(minLength: 16)

            Button { audio.playNext() }
            label:
            {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 26))
                    .opacity(queue.canAdvance ? 1.0 : 0.35)
            }
            .buttonStyle(SilverCircleButtonStyle(size: 64))
            .disabled(!queue.canAdvance)

            Spacer(minLength: 12)
            repeatToggle
        }
        // Negative top padding pulls the transport row 8 pt up
        // toward the scrubber, tightening the visual grouping of
        // "scrub + control" and putting more breathing room below
        // the buttons.
        .padding(.top, -8)
    }

    // Shuffle: simple SF Symbol toggle. Tint flips to accent when on
    // (matches the desktop's "active = highlighted" mod-button
    // treatment). 44 x 44 hit area satisfies the iOS minimum touch
    // target while the glyph itself sits at 22 pt so the button
    // doesn't visually compete with the silver discs.
    @ViewBuilder
    private var shuffleToggle: some View
    {
        Button
        {
            queue.setShuffled(!queue.isShuffled)
        }
        label:
        {
            Image(systemName: "shuffle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(queue.isShuffled ? Color.accentColor
                                                  : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Repeat: cycles off -> all -> one -> off. Mode "all" uses the
    // plain repeat glyph in accent colour; mode "one" swaps to
    // repeat.1 (the variant with the "1" indicator). Off uses the
    // plain glyph in secondary.
    @ViewBuilder
    private var repeatToggle: some View
    {
        Button
        {
            queue.cycleRepeatMode()
        }
        label:
        {
            Image(systemName: queue.repeatMode == .one ? "repeat.1" : "repeat")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(queue.repeatMode == .off ? Color.secondary
                                                          : Color.accentColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// Row used by the Suggested Tracks section. Same compact 36 pt thumb +
// title block as UpNextRow, but the trailing edge has TWO icon buttons
// instead of a duration label: a blue "+" that adds the suggestion to
// the queue, and a red "X" that passes (dismisses) it. The pair sits
// in a tight inner HStack so they read as a button group rather than
// drifting apart with the row's outer spacing.
private struct SuggestedTrackRow: View
{
    let track:  Track
    let onAdd:  () -> Void
    let onPass: () -> Void

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
            HStack(spacing: 8)
            {
                addButton
                passButton
            }
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
    private var addButton: some View
    {
        Button
        {
            onAdd()
        }
        label:
        {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var passButton: some View
    {
        Button
        {
            onPass()
        }
        label:
        {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

