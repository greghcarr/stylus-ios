import SwiftUI

@main
struct StylusApp: App
{
    @StateObject private var folder  = MusicFolderStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var queue:    PlayQueue
    @StateObject private var audio:    AudioPlayer
    @StateObject private var analysis: AnalysisController
    private let nowPlaying:           NowPlayingController

    init()
    {
        Stylus_Initialize()
        let q   = PlayQueue()
        let a   = AudioPlayer(queue: q)
        let lib = LibraryStore()
        // Re-binding library to the StateObject below keeps a single source
        // of truth: AnalysisController holds a weak ref to the same
        // instance that body's environmentObject(library) hands down.
        _queue    = StateObject(wrappedValue: q)
        _audio    = StateObject(wrappedValue: a)
        _library  = StateObject(wrappedValue: lib)
        _analysis = StateObject(wrappedValue: AnalysisController(library: lib))
        nowPlaying = NowPlayingController(audio: a)
    }

    var body: some Scene
    {
        WindowGroup
        {
            RootView()
                .environmentObject(folder)
                .environmentObject(library)
                .environmentObject(queue)
                .environmentObject(audio)
                .environmentObject(analysis)
                .task
                {
                    if let url = folder.folderURL { library.scan(folder: url) }
                }
        }
    }
}
