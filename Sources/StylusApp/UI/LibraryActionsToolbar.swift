import SwiftUI
import UniformTypeIdentifiers

// Reusable toolbar attached to every top-level tab root (All Music
// / Artists / Albums / Podcasts / Search). Provides the trailing
// "ellipsis.circle" overflow menu (rescan, change folder,
// analyse, look up artwork...) that previously lived only in the
// All Music view, plus the .fileImporter sheets it triggers, plus
// the scan-progress spinner that replaces the menu while the
// background scan is running.
//
// Placed here so adding a tab is one place: the new tab view just
// needs `.libraryActionsToolbar()` next to its `.tabTitleMenu(...)`.
struct LibraryActionsToolbar: ViewModifier
{
    @EnvironmentObject var library:  LibraryStore
    @EnvironmentObject var folder:   MusicFolderStore
    @EnvironmentObject var analysis: AnalysisController
    @EnvironmentObject var lookup:   LookupController

    @State private var showMusicPicker:   Bool = false
    @State private var showPodcastPicker: Bool = false

    func body(content: Content) -> some View
    {
        content
            .toolbar { menuToolbar }
            .fileImporter(
                isPresented:         $showMusicPicker,
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
                isPresented:         $showPodcastPicker,
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
        library.scan(music:   folder.musicFolderURL,
                     podcast: folder.podcastFolderURL)
    }

    @ToolbarContentBuilder
    private var menuToolbar: some ToolbarContent
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
}

extension View
{
    func libraryActionsToolbar() -> some View
    {
        modifier(LibraryActionsToolbar())
    }
}
