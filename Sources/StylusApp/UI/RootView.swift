import SwiftUI

// Top-level chrome. Two layers in a ZStack:
//   - Tabs layer: TabView (Library / Artists / Albums / Podcasts /
//     Search) with the persistent TransportBar pinned via
//     .safeAreaInset(.bottom). Fades opacity when the player expands.
//   - Player card: TransportBar OR full-screen NowPlayingSheet,
//     selected on `isExpanded`. matchedGeometryEffect on a shared
//     "playerCard" id so the bar's frame morphs into the full-screen
//     frame on tap or swipe-up, and back on close / drag-down.
struct RootView: View
{
    @EnvironmentObject var folder:  MusicFolderStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var queue:   PlayQueue
    @EnvironmentObject var audio:   AudioPlayer

    @Namespace private var nowPlayingNS
    @State    private var isExpanded   = false
    // 0 when the sheet is at rest, → 1 as the user drags it toward
    // dismissal. Drives a continuous tab-bar fade-in during the drag so
    // the user sees the destination materialising under their finger.
    @State    private var dragProgress: CGFloat = 0

    private static let expansion = Animation.spring(response: 0.45,
                                                     dampingFraction: 0.86)

    var body: some View
    {
        ZStack
        {
            tabsLayer
                .opacity(tabsOpacity)
                .allowsHitTesting(!isExpanded)

            if isExpanded
            {
                NowPlayingSheet(
                    onDismiss:            { collapse() },
                    onDragProgressChange: { dragProgress = $0 }
                )
                .matchedGeometryEffect(id: "playerCard",
                                       in: nowPlayingNS,
                                       anchor: .bottom)
                .zIndex(2)
            }
        }
        .animation(Self.expansion, value: isExpanded)
    }

    private var tabsOpacity: Double
    {
        if !isExpanded { return 1 }
        // While expanded, fade the tabs IN as the user drags the sheet
        // toward dismissal: 0 at rest, 1 when the drag reaches the
        // dismiss threshold.
        return Double(dragProgress)
    }

    private var tabsLayer: some View
    {
        TabView
        {
            NavigationStack { LibraryListView() }
                .withTransportBar(namespace: nowPlayingNS,
                                  isExpanded: isExpanded,
                                  onPresent: { expand() })
                .tabItem { Label("Library", systemImage: "music.note.list") }

            NavigationStack { ArtistsView() }
                .withTransportBar(namespace: nowPlayingNS,
                                  isExpanded: isExpanded,
                                  onPresent: { expand() })
                .tabItem { Label("Artists", systemImage: "music.mic") }

            NavigationStack { AlbumsView() }
                .withTransportBar(namespace: nowPlayingNS,
                                  isExpanded: isExpanded,
                                  onPresent: { expand() })
                .tabItem { Label("Albums", systemImage: "square.stack") }

            if folder.podcastFolderURL != nil
            {
                NavigationStack { PodcastsView() }
                    .withTransportBar(namespace: nowPlayingNS,
                                      isExpanded: isExpanded,
                                      onPresent: { expand() })
                    .tabItem { Label("Podcasts", systemImage: "mic") }
            }

            NavigationStack { SearchView() }
                .withTransportBar(namespace: nowPlayingNS,
                                  isExpanded: isExpanded,
                                  onPresent: { expand() })
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }

    private func expand()
    {
        withAnimation(Self.expansion) { isExpanded = true }
    }

    private func collapse()
    {
        withAnimation(Self.expansion)
        {
            isExpanded   = false
            dragProgress = 0
        }
    }
}

private extension View
{
    // Pins the small transport bar via .safeAreaInset(.bottom) only when
    // the player is collapsed; when expanded the bar is hidden because
    // the matchedGeometryEffect destination view (NowPlayingSheet) is
    // taking its place at full-screen size.
    func withTransportBar(namespace:  Namespace.ID,
                          isExpanded: Bool,
                          onPresent:  @escaping () -> Void) -> some View
    {
        safeAreaInset(edge: .bottom)
        {
            if !isExpanded
            {
                TransportBar(onTap: onPresent)
                    .matchedGeometryEffect(id: "playerCard",
                                           in: namespace,
                                           anchor: .bottom)
            }
        }
    }
}
