import SwiftUI
import UniformTypeIdentifiers

// Library tab: flat list of every scanned music track (podcasts excluded
// when a separate podcasts folder is configured). Other surfaces (Artists,
// Albums, Podcasts, Search) are separate views in the parent RootView's
// TabView.
//
// Wrapped in a NavigationStack by RootView. The persistent TransportBar
// and the NowPlayingSheet live at the RootView level so every tab shares
// them.
struct LibraryListView: View
{
    @EnvironmentObject var library:  LibraryStore
    @EnvironmentObject var folder:   MusicFolderStore
    @EnvironmentObject var analysis: AnalysisController
    @EnvironmentObject var lookup:   LookupController

    @State private var showMusicPicker:   Bool = false
    @State private var showPodcastPicker: Bool = false

    var body: some View
    {
        content
            .navigationTitle("Library")
            .toolbar { toolbar }
            .fileImporter(
                isPresented: $showMusicPicker,
                allowedContentTypes: [.folder]
            )
            { result in
                if case .success(let url) = result
                {
                    folder.setMusic(url: url)
                    rescan()
                }
            }
            .fileImporter(
                isPresented: $showPodcastPicker,
                allowedContentTypes: [.folder]
            )
            { result in
                if case .success(let url) = result
                {
                    folder.setPodcast(url: url)
                    rescan()
                }
            }
    }

    private func rescan()
    {
        library.scan(music: folder.musicFolderURL,
                     podcast: folder.podcastFolderURL)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent
    {
        ToolbarItem(placement: .topBarTrailing)
        {
            if library.isScanning
            {
                ProgressView()
            }
            else if folder.musicFolderURL != nil
            {
                Menu
                {
                    Button("Rescan") { rescan() }

                    Button("Change music folder…")
                    {
                        showMusicPicker = true
                    }

                    if folder.podcastFolderURL != nil
                    {
                        Button("Change podcasts folder…")
                        {
                            showPodcastPicker = true
                        }
                        Button(role: .destructive)
                        {
                            folder.clearPodcast()
                            rescan()
                        }
                        label:
                        {
                            Label("Remove podcasts folder",
                                  systemImage: "minus.circle")
                        }
                    }
                    else
                    {
                        Button
                        {
                            showPodcastPicker = true
                        }
                        label:
                        {
                            Label("Choose podcasts folder…",
                                  systemImage: "mic.badge.plus")
                        }
                    }

                    Divider()

                    if analysis.isAnalysing
                    {
                        Button(role: .destructive) { analysis.cancelAll() }
                        label:
                        {
                            Label("Stop analysing (\(analysis.queueDepth) left)",
                                  systemImage: "stop.circle")
                        }
                    }
                    else
                    {
                        Button { analysis.enqueueUnanalysed(library.tracks) }
                        label:
                        {
                            Label("Analyse library", systemImage: "waveform")
                        }
                    }

                    if lookup.inProgress
                    {
                        Button(role: .destructive) { lookup.cancelAll() }
                        label:
                        {
                            Label("Stop lookup (\(lookup.queueDepth) left)",
                                  systemImage: "stop.circle")
                        }
                    }
                    else
                    {
                        Button { lookup.enqueueAllArtOnly(library.tracks) }
                        label:
                        {
                            Label("Look up missing artwork",
                                  systemImage: "photo.on.rectangle.angled")
                        }
                    }
                }
                label:
                {
                    if analysis.isAnalysing || lookup.inProgress
                    {
                        ProgressView().controlSize(.small)
                    }
                    else
                    {
                        Image(systemName: "ellipsis.circle")
                    }
                }
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
            ForEach(musicTracks)
            { track in
                TrackRowButton(track: track, visibleTracks: musicTracks)
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var chooseFolderState: some View
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
        .padding()
    }

    @ViewBuilder
    private var emptyState: some View
    {
        if library.isScanning
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
            .padding()
        }
        else
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
            .padding()
        }
    }
}
