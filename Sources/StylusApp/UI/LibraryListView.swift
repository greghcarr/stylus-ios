import SwiftUI
import UniformTypeIdentifiers

struct LibraryListView: View
{
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var audio:   AudioPlayer
    @EnvironmentObject var queue:   PlayQueue
    @EnvironmentObject var folder:  MusicFolderStore

    @State private var showFolderPicker = false

    var body: some View
    {
        NavigationStack
        {
            VStack(spacing: 0)
            {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TransportBar()
            }
            .navigationTitle("Library")
            .toolbar { toolbar }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        )
        { result in
            if case .success(let url) = result
            {
                folder.set(url: url)
                library.scan(folder: url)
            }
        }
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
            else if folder.folderURL != nil
            {
                Menu
                {
                    Button("Rescan")
                    {
                        if let url = folder.folderURL { library.scan(folder: url) }
                    }
                    Button("Change folder…")
                    {
                        showFolderPicker = true
                    }
                }
                label:
                {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View
    {
        if folder.folderURL == nil
        {
            chooseFolderState
        }
        else if library.tracks.isEmpty
        {
            emptyState
        }
        else
        {
            trackList
        }
    }

    private var trackList: some View
    {
        List(Array(library.tracks.enumerated()), id: \.element.id)
        { (index, track) in
            Button
            {
                playFromRow(at: index)
            }
            label:
            {
                TrackRow(track: track,
                         isPlaying: audio.currentTrack?.filePath == track.filePath)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    // Mirrors the desktop's "tap a row, queue this row to end of view" rule.
    // The library's current order is what becomes the queue.
    private func playFromRow(at index: Int)
    {
        let tracks = library.tracks
        guard index >= 0, index < tracks.count else { return }
        queue.setQueue(tracks, startingAt: index)
        if let t = queue.currentTrack { audio.play(t) }
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
            Button("Choose Music Folder…")
            {
                showFolderPicker = true
            }
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
                if let url = folder.folderURL
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

private struct TrackRow: View
{
    let track:     Track
    let isPlaying: Bool

    @State private var artwork: UIImage?

    var body: some View
    {
        HStack(spacing: 12)
        {
            artworkThumb
            VStack(alignment: .leading, spacing: 2)
            {
                Text(track.displayTitle)
                    .lineLimit(1)
                if !track.subtitle.isEmpty
                {
                    Text(track.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            trailingMetadata
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .task(id: track.filePath)
        {
            artwork = await loadArtwork(for: track.filePath)
        }
    }

    @ViewBuilder
    private var artworkThumb: some View
    {
        Group
        {
            if let artwork = artwork
            {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            else
            {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var trailingMetadata: some View
    {
        VStack(alignment: .trailing, spacing: 2)
        {
            if !analysisLine.isEmpty
            {
                Text(analysisLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4)
            {
                if isPlaying
                {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                Text(track.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var analysisLine: String
    {
        var parts: [String] = []
        if !track.formattedBpm.isEmpty { parts.append(track.formattedBpm) }
        if !track.key.isEmpty           { parts.append(track.key) }
        return parts.joined(separator: " ")
    }
}
