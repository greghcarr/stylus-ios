import SwiftUI

// Top-level chrome: TabView with Library / Artists / Albums / Search
// always; Podcasts only when a podcast folder is set. The persistent
// TransportBar pins via .safeAreaInset(.bottom) on each tab's
// NavigationStack rather than on the TabView itself, so the bar sits
// above the system tab bar instead of competing with it. The
// NowPlayingSheet presentation lives at this level so any tab can lift
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

            if folder.podcastFolderURL != nil
            {
                NavigationStack { PodcastsView() }
                    .withTransportBar(showNowPlaying: $showNowPlaying)
                    .tabItem { Label("Podcasts", systemImage: "mic") }
            }

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
