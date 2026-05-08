import SwiftUI

@main
struct StylusApp: App
{
    @StateObject private var folder    = MusicFolderStore()
    @StateObject private var library   = LibraryStore()
    @StateObject private var playlists = PlaylistStore()
    @StateObject private var queue:    PlayQueue
    @StateObject private var audio:    AudioPlayer
    @StateObject private var analysis: AnalysisController
    @StateObject private var lookup:   LookupController
    private let nowPlaying:           NowPlayingController

    init()
    {
        Stylus_Initialize()
        let q   = PlayQueue()
        let a   = AudioPlayer(queue: q)
        let lib = LibraryStore()
        // Re-binding library to the StateObject below keeps a single source
        // of truth: Analysis / Lookup controllers hold a weak ref to the
        // same instance that body's environmentObject(library) hands down.
        _queue    = StateObject(wrappedValue: q)
        _audio    = StateObject(wrappedValue: a)
        _library  = StateObject(wrappedValue: lib)
        _analysis = StateObject(wrappedValue: AnalysisController(library: lib))
        _lookup   = StateObject(wrappedValue: LookupController(library: lib))
        nowPlaying = NowPlayingController(audio: a)
    }

    var body: some Scene
    {
        WindowGroup
        {
            // SplashView shows the app icon for a short beat then
            // fades to RootView. Environment objects are injected
            // here at the WindowGroup level so they reach RootView
            // when SplashView swaps it in. The library scan is
            // started here too -- by the time the splash fades out
            // the cache load (and possibly the skip-scan) has
            // already completed, so the app's first list view shows
            // tracks immediately rather than blank.
            SplashView()
                .environmentObject(folder)
                .environmentObject(library)
                .environmentObject(playlists)
                .environmentObject(queue)
                .environmentObject(audio)
                .environmentObject(analysis)
                .environmentObject(lookup)
                .task
                {
                    if folder.musicFolderURL != nil
                    {
                        library.scan(music:   folder.musicFolderURL,
                                     podcast: folder.podcastFolderURL)
                    }
                    // Self-heal playlist trackPaths against the
                    // (now-loaded) library so any path stored under
                    // an older sandbox-container UUID gets rewritten
                    // to the current one. No-op when nothing's stale.
                    // library.scan synchronously populates tracks
                    // from the on-disk cache before returning, so
                    // libraryTracks is non-empty here even when the
                    // background scan hasn't finished yet.
                    playlists.migratePathsIfNeeded(against: library.tracks)
                }
        }
    }
}
