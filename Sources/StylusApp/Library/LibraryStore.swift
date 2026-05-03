import Foundation

final class LibraryStore: ObservableObject
{
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isScanning: Bool = false

    private var handle: StylusLibraryHandle?

    deinit
    {
        if let h = handle { Stylus_LibraryDestroy(h) }
    }

    // Convenience: caller is expected to have an active security scope on the
    // URL for the duration of the scan and any subsequent playback.
    func scan(folder url: URL)
    {
        scan(folders: [url.path])
    }

    func scan(folders: [String])
    {
        if let h = handle
        {
            Stylus_LibraryDestroy(h)
            handle = nil
        }
        tracks.removeAll()
        isScanning = true

        let owned: [UnsafeMutablePointer<CChar>?] = folders.map { strdup($0) }
        defer { owned.forEach { if let p = $0 { free(p) } } }
        var ptrs: [UnsafePointer<CChar>?] = owned.map { $0.map { UnsafePointer($0) } }

        ptrs.withUnsafeMutableBufferPointer
        { buf in
            handle = Stylus_LibraryCreate(buf.baseAddress, Int32(folders.count))
        }

        let user = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        Stylus_LibraryStartScan(handle,
                                libraryStoreOnTrack,
                                libraryStoreOnScanDone,
                                user)
    }

    fileprivate func appendTrack(_ track: Track)
    {
        tracks.append(track)
    }

    fileprivate func scanCompleted()
    {
        isScanning = false
    }
}

// JUCE's MessageManager dispatches the scanner's batch + done callbacks to the
// main thread, so these C callbacks already run on the main thread.

private func libraryStoreOnTrack(trackPtr: UnsafePointer<StylusTrackC>?,
                                 userData:  UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let store = Unmanaged<LibraryStore>.fromOpaque(userData).takeUnretainedValue()
    store.appendTrack(Track(c: trackPtr.pointee))
}

private func libraryStoreOnScanDone(total: Int32,
                                    userData: UnsafeMutableRawPointer?)
{
    guard let userData = userData else { return }
    let store = Unmanaged<LibraryStore>.fromOpaque(userData).takeUnretainedValue()
    store.scanCompleted()
}
