import SwiftUI

// Top-level chrome.
//
// The Now Playing sheet's vertical position is owned by ONE state
// variable, sheetY:
//   sheetY = 0       → sheet fully expanded (covers screen)
//   sheetY = screenH → sheet entirely off-screen below the mini-bar
// Lift drag from the TransportBar and dismiss drag inside the sheet
// both write to sheetY, so the upward swipe is fully finger-tracking
// in the same way the downward swipe is. Tap-to-present and the close
// button just animate sheetY between the two endpoints.
struct RootView: View
{
    @EnvironmentObject var folder:  MusicFolderStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var queue:   PlayQueue
    @EnvironmentObject var audio:   AudioPlayer

    // Start with a large sentinel so the sheet is "off-screen" before
    // we measure the actual screen height. The background
    // GeometryReader clamps it to screenH on first appear.
    // Top-level tab selection lives in a TabRouter so any tab's
    // toolbar title menu can flip to a different tab without having
    // to plumb a @Binding through every view. RootView owns the
    // instance; .environmentObject below makes it visible to every
    // descendant.
    @StateObject private var router  = TabRouter()

    @State private var sheetY:  CGFloat = 9999
    @State private var screenH: CGFloat = 1000
    // Top safe-area inset captured on appear. The lift gesture
    // reports the finger's location in global (screen-coords) space,
    // but sheetY is interpreted relative to the ZStack's frame,
    // which respects the safe area -- sheetY = 0 places the sheet's
    // top at safe_area_top. We subtract safeTop when converting from
    // global location to sheetY so the sheet's top lands exactly
    // under the finger, no constant delta.
    @State private var safeTop: CGFloat = 0

    // Lift threshold (pt of upward drag) past which a release commits
    // to fully-expanded. Below it, the sheet snaps back to the bar.
    private static let liftThreshold: CGFloat = 100

    private static let expansion = Animation.spring(response: 0.42,
                                                     dampingFraction: 0.86)
    private static let collapse  = Animation.spring(response: 0.22,
                                                     dampingFraction: 1.0)

    var body: some View
    {
        ZStack
        {
            tabsLayer
                // Pin the underlying tabs to fill the ZStack at all
                // times. Without this, the ZStack sizes itself to
                // max(child.intrinsicSize); inserting / removing
                // NowPlayingSheet from the conditional below shifts
                // the ZStack's frame by a pt or two, and tabsLayer
                // (centered within the ZStack by default) appears to
                // slide horizontally. Locking the frame keeps the
                // tab content stationary across sheet presentations.
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // NowPlayingSheet is rendered unconditionally and just
            // offset off-screen via sheetY when it shouldn't be
            // visible. Conditional rendering (even the narrower
            // `currentTrack != nil`) caused every nil → non-nil
            // transition to insert the sheet into the ZStack,
            // which reset the underlying List's UIScrollView state
            // and toggled the trailing scroll-indicator track --
            // visible to the user as a ~3 pt horizontal shrink
            // every time a song was selected after the queue had
            // emptied. Always-rendering keeps the children stable.
            //
            // The "no track" else branch in NowPlayingSheet shows a
            // simple "Nothing playing" placeholder; the user can't
            // actually reach it because TransportBar hides itself
            // when there's no current track, so there's no tap
            // affordance to expand the sheet during that state.
            NowPlayingSheet(
                sheetY:    $sheetY,
                onDismiss: { dismissSheet() }
            )
            .offset(y: max(0, sheetY))
        }
        // No scenePhase auto-present: the sheet is only ever lifted
        // by an explicit user gesture (tap the mini transport bar or
        // drag it up). Earlier we auto-presented on every transition
        // to .active so that lock-screen / dynamic-island taps would
        // land the user in the full sheet, but iOS doesn't actually
        // give us a "user tapped the now-playing widget" signal -- it
        // looks identical to any other refocus -- so the heuristic
        // ended up over-presenting (Control Center dismissals,
        // returning from another app, etc.) and felt aggressive.
        //
        // When a track ends and the queue empties (currentTrack goes
        // nil), pre-park sheetY at screenH so the sheet's resident
        // view stays off-screen. Without this, if the user had the
        // sheet open while the last track played and never dismissed
        // it, sheetY would still be 0 by the time they pick another
        // song -- and the now-resident sheet would re-appear
        // unexpectedly. Resetting on the empty-queue boundary makes
        // the next song's playback start with a clean off-screen
        // sheet that only shows up if the user explicitly raises it.
        .onChange(of: audio.currentTrack?.filePath)
        { _, newPath in
            if newPath == nil { sheetY = screenH }
        }
        // Custom env key (NOT .environmentObject) so consumers don't
        // subscribe to the router's @Published current. See the
        // explanation above the TabRouter declaration in
        // TabNavigation.swift.
        .environment(\.tabRouter, router)
        // Background GeometryReader captures screen height + bottom
        // safe area so we know how far the sheet has to travel to be
        // fully off-screen. Doesn't affect layout (Color.clear).
        .background
        {
            GeometryReader
            { geo in
                Color.clear
                    .onAppear
                    {
                        let H = geo.size.height + geo.safeAreaInsets.bottom
                        screenH = H
                        safeTop = geo.safeAreaInsets.top
                        if sheetY > H { sheetY = H }
                    }
                    .onChange(of: geo.size.height)
                    {
                        let H = geo.size.height + geo.safeAreaInsets.bottom
                        // If the sheet was at rest off-screen, follow
                        // the new H. Otherwise leave it where it is so
                        // an in-progress drag isn't disturbed.
                        if abs(sheetY - screenH) < 1 { sheetY = H }
                        screenH = H
                        safeTop = geo.safeAreaInsets.top
                    }
            }
        }
    }

    private var tabsLayer: some View
    {
        // Single NavigationStack with HomeView at the root. Tapping
        // a row in HomeView pushes the destination via
        // NavigationLink(value: AppTab) -- gives us iOS's standard
        // slide-in-from-the-right animation, matching what the user
        // already sees when drilling from Artists into a specific
        // artist. The leading "Home" back button in tabTitleMenu
        // calls @Environment(\.dismiss) so it pops back to HomeView
        // with the equivalent slide-out animation.
        //
        // Drill-down inside a destination tab (e.g., Artists ->
        // ArtistDetailView) is a further push onto the same stack,
        // so its back button is auto-generated by NavigationStack
        // and pops back to the tab root.
        NavigationStack(path: $router.path)
        {
            HomeView()
                .navigationDestination(for: AppTab.self)
                { tab in
                    destination(for: tab)
                }
        }
        .safeAreaInset(edge: .bottom) { transportBar }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View
    {
        switch tab
        {
        case .home:      HomeView()
        case .library:   LibraryListView()
        case .artists:   ArtistsView()
        case .albums:    AlbumsView()
        case .genres:    GenresView()
        case .playlists: PlaylistsView()
        case .podcasts:
            if folder.podcastFolderURL != nil
            {
                PodcastsView()
            }
            else
            {
                // Shouldn't normally render -- HomeView omits the
                // Podcasts row when no podcast folder is set.
                HomeView()
            }
        case .search:    SearchView()
        }
    }

    private var transportBar: some View
    {
        TransportBar(
            onTap:      { presentSheet() },
            onLiftDrag: { y   in liftDragChanged(locationY: y) },
            onLiftEnd:  { dy  in liftDragEnded(translationHeight: dy) }
        )
    }

    private func presentSheet()
    {
        // Snap to off-screen first (no animation) so the spring has
        // somewhere to start from in case the user re-tapped right
        // after a partial drag.
        if sheetY < screenH * 0.5 { return }
        sheetY = screenH
        withAnimation(Self.expansion) { sheetY = 0 }
    }

    private func dismissSheet()
    {
        withAnimation(Self.collapse) { sheetY = screenH }
    }

    private func liftDragChanged(locationY: CGFloat)
    {
        // locationY is the finger's current Y in global (screen)
        // coords. Subtract safeTop to convert to the sheet's local
        // offset reference (sheetY = 0 places the sheet's top at
        // safe_area_top). With this, sheet's top tracks finger.y
        // exactly -- pull up from anywhere on the bar and the
        // sheet's top is right under the finger.
        sheetY = min(screenH, max(0, locationY - safeTop))
    }

    private func liftDragEnded(translationHeight: CGFloat)
    {
        if translationHeight < -Self.liftThreshold
        {
            withAnimation(Self.expansion) { sheetY = 0 }
        }
        else
        {
            withAnimation(Self.collapse) { sheetY = screenH }
        }
    }
}
