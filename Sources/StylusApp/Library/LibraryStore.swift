import Foundation

final class LibraryStore: ObservableObject
{
    @Published private(set) var tracks:     [Track] = []
    @Published private(set) var isScanning: Bool    = false

    private var handle:     StylusLibraryHandle?
    // Holds the in-flight fresh-scan results. When the scan completes we swap
    // this in for `tracks` atomically, so the UI sees the cached library
    // continuously and then jumps to the fresh one in a single update.
    private var scanBuffer: [Track] = []

    deinit
    {
        if let h = handle { Stylus_LibraryDestroy(h) }
    }

    // Caller is expected to have an active security scope on the URL for the
    // duration of the scan and any subsequent playback.
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
        scanBuffer.removeAll()
        isScanning = true

        let owned: [UnsafeMutablePointer<CChar>?] = folders.map { strdup($0) }
        defer { owned.forEach { if let p = $0 { free(p) } } }
        var ptrs: [UnsafePointer<CChar>?] = owned.map { $0.map { UnsafePointer($0) } }

        ptrs.withUnsafeMutableBufferPointer
        { buf in
            handle = Stylus_LibraryCreate(buf.baseAddress, Int32(folders.count))
        }

        let user = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // Phase 1: instant repopulate from the on-disk cache. Fires
        // libraryStoreOnCachedTrack once per cached track on this thread.
        _ = Stylus_LibraryLoadCache(handle, libraryStoreOnCachedTrack, user)

        // Phase 2: kick off the fresh background scan. Scanned tracks
        // accumulate in scanBuffer; the cached `tracks` stay visible until
        // libraryStoreOnScanDone swaps them in atomically.
        Stylus_LibraryStartScan(handle,
                                libraryStoreOnScannedTrack,
                                libraryStoreOnScanDone,
                                user)
    }

    fileprivate func appendCachedTrack(_ track: Track)
    {
        tracks.append(track)
    }

    fileprivate func appendScannedTrack(_ track: Track)
    {
        scanBuffer.append(track)
    }

    fileprivate func scanCompleted()
    {
        // Atomic swap: replace the (possibly stale) cached library with the
        // fresh scan results. Single SwiftUI invalidation.
        tracks     = scanBuffer
        scanBuffer = []
        isScanning = false
    }
}

// JUCE's MessageManager dispatches the scanner's batch + done callbacks to the
// main thread, so these C callbacks already run on the main thread.

private func libraryStoreOnCachedTrack(trackPtr: UnsafePointer<StylusTrackC>?,
                                       userData:  UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let store = Unmanaged<LibraryStore>.fromOpaque(userData).takeUnretainedValue()
    store.appendCachedTrack(Track(c: trackPtr.pointee))
}

private func libraryStoreOnScannedTrack(trackPtr: UnsafePointer<StylusTrackC>?,
                                        userData:  UnsafeMutableRawPointer?)
{
    guard let trackPtr = trackPtr, let userData = userData else { return }
    let store = Unmanaged<LibraryStore>.fromOpaque(userData).takeUnretainedValue()
    store.appendScannedTrack(Track(c: trackPtr.pointee))
}

private func libraryStoreOnScanDone(total:    Int32,
                                    userData: UnsafeMutableRawPointer?)
{
    guard let userData = userData else { return }
    let store = Unmanaged<LibraryStore>.fromOpaque(userData).takeUnretainedValue()
    store.scanCompleted()
}
