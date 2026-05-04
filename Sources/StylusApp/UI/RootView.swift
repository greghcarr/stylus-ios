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
    @State    private var isExpanded = false

    private static let expansion = Animation.spring(response: 0.45,
                                                     dampingFraction: 0.86)

    var body: some View
    {
        ZStack
        {
            tabsLayer
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(!isExpanded)

            if isExpanded
            {
                NowPlayingSheet(onDismiss: { collapse() })
                    .matchedGeometryEffect(id: "playerCard",
                                           in: nowPlayingNS,
                                           anchor: .bottom)
                    .zIndex(2)
            }
        }
        .animation(Self.expansion, value: isExpanded)
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
        withAnimation(Self.expansion) { isExpanded = false }
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
