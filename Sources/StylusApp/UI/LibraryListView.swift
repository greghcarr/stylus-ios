import SwiftUI
import UniformTypeIdentifiers

// All Music tab: flat list of every scanned music track (podcasts
// excluded when a separate podcasts folder is configured). Other
// surfaces (Artists, Albums, Podcasts, Search) are separate views
// in the parent RootView's TabView.
//
// Wrapped in a NavigationStack by RootView. The persistent
// TransportBar and the NowPlayingSheet live at the RootView level
// so every tab shares them. The trailing overflow menu (rescan /
// change folder / analyse / look up) lives in the shared
// .libraryActionsToolbar() modifier in LibraryActionsToolbar.swift.
struct LibraryListView: View
{
    @EnvironmentObject var library:  LibraryStore
    @EnvironmentObject var folder:   MusicFolderStore

    // Drives the empty-state "Choose Music Folder…" button shown
    // when no music folder has been picked yet. The shared
    // .libraryActionsToolbar() modifier handles the toolbar's
    // "Change music folder…" menu item with its own state and its
    // own fileImporter, so this is intentionally separate.
    @State private var showMusicPicker: Bool = false

    var body: some View
    {
        content
            .tabTitleMenu("All Songs")
            .libraryActionsToolbar(scope: .music)
            .fileImporter(
                isPresented:         $showMusicPicker,
                allowedContentTypes: [.folder]
            )
            { result in
                if case .success(let url) = result
                {
                    folder.setMusic(url: url)
                    library.scan(music:   folder.musicFolderURL,
                                 podcast: folder.podcastFolderURL)
                }
            }
    }

    @ViewBuilder
    private var content: some View
    {
        if folder.musicFolderURL == nil
        {
            chooseFolderState
        }
        else if library.tracks.contains(where: { !$0.isPodcast })
        {
            trackList
        }
        else
        {
            emptyState
        }
    }

    private var trackList: some View
    {
        let musicTracks = library.tracks.filter { !$0.isPodcast }
        return List
        {
            ForEach(Array(musicTracks.enumerated()), id: \.element.id)
            { (index, track) in
                TrackRowButton(track: track, visibleTracks: musicTracks)
                    .hideFirstRowSeparator(index == 0)
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        // Hide the implicit section's top separator -- the thin line
        // above the first row that SwiftUI's plain list draws by
        // default.
        .listSectionSeparator(.hidden)
    }

    // Wraps an empty-state block so it lands at the centre of the
    // SCREEN regardless of the surrounding view's content insets.
    // .ignoresSafeArea() is what does the screen-vs-content-area
    // distinction: without it the nav bar above and TransportBar below
    // squeeze the available area asymmetrically, so the geometric
    // centre lands slightly below the screen's actual centre. See the
    // matching note in EmptyStateView for the full reasoning.
    @ViewBuilder
    private func centered<C: View>(@ViewBuilder _ content: () -> C) -> some View
    {
        HStack(spacing: 0)
        {
            Spacer(minLength: 0)
            content()
                .padding()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var chooseFolderState: some View
    {
        centered
        {
            VStack(spacing: 16)
            {
                Image(systemName: "folder.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Pick your music folder").font(.headline)
                Text("Choose a folder in iCloud Drive, on this iPhone, or on an external drive. Stylus will scan it and other apps can read the same files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Choose Music Folder…") { showMusicPicker = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View
    {
        if library.isScanning
        {
            centered
            {
                VStack(spacing: 12)
                {
                    ProgressView()
                    Text("Scanning…")
                    if library.expectedCount > 0
                    {
                        ProgressView(value: Double(library.scannedCount),
                                     total: Double(library.expectedCount))
                            .progressViewStyle(.linear)
                            .tint(.green)
                            .frame(width: 240)
                        Text("\(library.scannedCount) / \(library.expectedCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        else
        {
            centered
            {
                VStack(spacing: 8)
                {
                    Image(systemName: "music.note.list")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No tracks found").font(.headline)
                    if let url = folder.musicFolderURL
                    {
                        Text(url.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Text("Add audio files to that folder, then tap Rescan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }
}
