import SwiftUI

@main
struct StylusApp: App
{
    @StateObject private var folder  = MusicFolderStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var audio   = AudioPlayer()

    init()
    {
        Stylus_Initialize()
    }

    var body: some Scene
    {
        WindowGroup
        {
            LibraryListView()
                .environmentObject(folder)
                .environmentObject(library)
                .environmentObject(audio)
                .task
                {
                    if let url = folder.folderURL { library.scan(folder: url) }
                }
        }
    }
}
