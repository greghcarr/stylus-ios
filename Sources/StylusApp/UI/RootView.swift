import SwiftUI

// Top-level chrome: TabView with the four library surfaces, the persistent
// TransportBar pinned above the system tab bar via .safeAreaInset, and the
// NowPlayingSheet that any tab can lift up via the bar's tap.
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
                .tabItem { Label("Library", systemImage: "music.note.list") }

            NavigationStack { ArtistsView() }
                .tabItem { Label("Artists", systemImage: "music.mic") }

            NavigationStack { AlbumsView() }
                .tabItem { Label("Albums", systemImage: "square.stack") }

            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .safeAreaInset(edge: .bottom)
        {
            TransportBar(onTap: { showNowPlaying = true })
        }
        .sheet(isPresented: $showNowPlaying)
        {
            NowPlayingSheet()
        }
    }
}
