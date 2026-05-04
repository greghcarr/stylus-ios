import SwiftUI

// Top-level chrome: TabView with the four library surfaces, the persistent
// TransportBar pinned via .safeAreaInset(.bottom) ON EACH TAB rather than
// on the TabView itself. Applied to the TabView the inset would compete
// with the system tab bar's slot and the tab bar would get hidden whenever
// the bar materialised (i.e. as soon as a track was current). Inside each
// tab the inset sits naturally between the tab content and the tab bar.
//
// The NowPlayingSheet presentation sits at this level so any tab can lift
// it via the bar's tap.
struct RootView: View
{
    @EnvironmentObject var folder:  MusicFolderStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var queue:   PlayQueue
    @EnvironmentObject var audio:   AudioPlayer

    @State private var showNowPlaying = false

    var body: some View
    {
        TabView
        {
            NavigationStack { LibraryListView() }
                .withTransportBar(showNowPlaying: $showNowPlaying)
                .tabItem { Label("Library", systemImage: "music.note.list") }

            NavigationStack { ArtistsView() }
                .withTransportBar(showNowPlaying: $showNowPlaying)
                .tabItem { Label("Artists", systemImage: "music.mic") }

            NavigationStack { AlbumsView() }
                .withTransportBar(showNowPlaying: $showNowPlaying)
                .tabItem { Label("Albums", systemImage: "square.stack") }

            NavigationStack { SearchView() }
                .withTransportBar(showNowPlaying: $showNowPlaying)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .sheet(isPresented: $showNowPlaying)
        {
            NowPlayingSheet()
        }
    }
}

private extension View
{
    func withTransportBar(showNowPlaying: Binding<Bool>) -> some View
    {
        safeAreaInset(edge: .bottom)
        {
            TransportBar(onTap: { showNowPlaying.wrappedValue = true })
        }
    }
}
