import SwiftUI

@main
struct StylusApp: App
{
    @StateObject private var folder  = MusicFolderStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var queue:    PlayQueue
    @StateObject private var audio:    AudioPlayer

    init()
    {
        Stylus_Initialize()
        let q = PlayQueue()
        _queue = StateObject(wrappedValue: q)
        _audio = StateObject(wrappedValue: AudioPlayer(queue: q))
    }

    var body: some Scene
    {
        WindowGroup
        {
            LibraryListView()
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
