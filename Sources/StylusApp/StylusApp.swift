import SwiftUI

@main
struct StylusApp: App
{
    @StateObject private var folder  = MusicFolderStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var queue:    PlayQueue
    @StateObject private var audio:    AudioPlayer
    private let nowPlaying:           NowPlayingController

    init()
    {
        Stylus_Initialize()
        let q = PlayQueue()
        let a = AudioPlayer(queue: q)
        _queue = StateObject(wrappedValue: q)
        _audio = StateObject(wrappedValue: a)
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
                .task
                {
                    if let url = folder.folderURL { library.scan(folder: url) }
                }
        }
    }
}
