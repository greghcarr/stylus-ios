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

    @Environment(\.scenePhase) private var scenePhase

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

            if audio.currentTrack != nil
            {
                // No backdrop layer behind the sheet -- the
                // tabsLayer (the active library / artists / etc.
                // tab) shows through above and around the sheet,
                // so as the user drags the sheet down they see
                // their main app emerge from behind it. The status
                // bar renders over whatever the underlying tab has
                // there (its own background, navigation chrome,
                // etc.).
                //
                // The condition is `currentTrack != nil` only --
                // intentionally NOT `&& sheetY < screenH`. With the
                // narrower condition, the sheet was inserted into
                // the view tree at every present and removed at
                // every dismiss, and SwiftUI rebuilt the whole
                // ZStack on each transition. That insertion was
                // resetting the underlying List's UIScrollView
                // state and toggling the trailing scroll-indicator
                // track in / out, visibly shifting list rows by
                // ~3 pt during the animation. Keeping the sheet
                // resident once a track is loaded -- and just
                // animating its offset -- holds the underlying
                // scroll views stable.
                NowPlayingSheet(
                    sheetY:    $sheetY,
                    onDismiss: { dismissSheet() }
                )
                .offset(y: max(0, sheetY))
            }
        }
        // Auto-present the Now Playing sheet whenever the app
        // becomes active and a track is loaded. Covers the typical
        // "user tapped the dynamic island / lock-screen controls
        // and was sent to the app" flow. presentSheet() early-
        // returns when the sheet is already up, so this is also
        // safe to fire on .inactive → .active transitions (e.g.
        // user pulled Control Center and dismissed it) -- the
        // sheet stays where it was rather than re-animating.
        .onChange(of: scenePhase)
        { _, newPhase in
            if newPhase == .active && audio.currentTrack != nil
            {
                presentSheet()
            }
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
