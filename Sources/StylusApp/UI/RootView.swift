import SwiftUI

// Top-level chrome. Two layers in a ZStack:
//   - Tabs layer: TabView (Library / Artists / Albums / Podcasts /
//     Search) with the persistent TransportBar pinned via
//     .safeAreaInset(.bottom). The bar is ALWAYS rendered (not
//     conditional on isExpanded) so its material background never
//     flickers in/out underneath the Now Playing sheet on collapse;
//     when expanded the sheet's full-screen frame simply covers it.
//   - Player card: when isExpanded, NowPlayingSheet renders on top.
//     matchedGeometryEffect on a shared "playerCard" id, with the bar
//     as the (always-present) source: on tap or swipe-up the bar's
//     frame morphs into the full-screen frame, and on collapse it
//     morphs back. Tabs fade based on the user's drag-down progress.
struct RootView: View
{
    @EnvironmentObject var folder:  MusicFolderStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var queue:   PlayQueue
    @EnvironmentObject var audio:   AudioPlayer

    @Namespace private var nowPlayingNS
    @State    private var isExpanded:  Bool    = false
    // Single shared source of truth for the user's drag-to-dismiss.
    // The sheet's offset and the tabs' fade-in both derive from this
    // value, so they can never render a frame apart.
    @State    private var dragOffset:  CGFloat = 0

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
                    dragOffset: $dragOffset,
                    onDismiss:  { collapse() }
                )
                .matchedGeometryEffect(id:       "playerCard",
                                       in:       nowPlayingNS,
                                       anchor:   .bottom,
                                       isSource: false)
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
        return Double(min(dragOffset / NowPlayingSheet.dismissThreshold, 1))
    }

    private var tabsLayer: some View
    {
        TabView
        {
            NavigationStack { LibraryListView() }
                .withTransportBar(namespace: nowPlayingNS,
                                  onPresent: { expand() })
                .tabItem { Label("Library", systemImage: "music.note.list") }

            NavigationStack { ArtistsView() }
                .withTransportBar(namespace: nowPlayingNS,
                                  onPresent: { expand() })
                .tabItem { Label("Artists", systemImage: "music.mic") }

            NavigationStack { AlbumsView() }
                .withTransportBar(namespace: nowPlayingNS,
                                  onPresent: { expand() })
                .tabItem { Label("Albums", systemImage: "square.stack") }

            if folder.podcastFolderURL != nil
            {
                NavigationStack { PodcastsView() }
                    .withTransportBar(namespace: nowPlayingNS,
                                      onPresent: { expand() })
                    .tabItem { Label("Podcasts", systemImage: "mic") }
            }

            NavigationStack { SearchView() }
                .withTransportBar(namespace: nowPlayingNS,
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
            isExpanded = false
            dragOffset = 0
        }
    }
}

private extension View
{
    // The TransportBar is always rendered in the bottom safe-area
    // inset, even while the player is expanded. That guarantees its
    // regularMaterial background is continuously present underneath
    // the sheet, so the moment the sheet's matched-geometry collapse
    // ends there's no transparent frame between them. The sheet's
    // matchedGeometryEffect uses the bar's frame as anchor.
    func withTransportBar(namespace: Namespace.ID,
                          onPresent: @escaping () -> Void) -> some View
    {
        safeAreaInset(edge: .bottom)
        {
            TransportBar(onTap: onPresent)
                .matchedGeometryEffect(id:       "playerCard",
                                       in:       namespace,
                                       anchor:   .bottom,
                                       isSource: true)
        }
    }
}
