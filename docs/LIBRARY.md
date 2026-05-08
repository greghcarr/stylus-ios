# Library

How the library scanner is fed, cached, throttled, and short-circuited
on launch.

## Folder picker + security scope
`UIFileSharingEnabled` only bootstraps "On My iPhone" visibility in Files;
the music itself lives outside the sandbox in a user-picked folder
(typically a top-level "On My iPhone" folder, or iCloud Drive / external
drive). `MusicFolderStore` runs `URL.bookmarkData()` after the
`fileImporter` callback and stores the bytes in `UserDefaults`. On launch
it resolves the bookmark and calls `startAccessingSecurityScopedResource()`
once; the scope stays active for the app lifetime so the C++ scanner and
`AVAudioPlayer` can read by POSIX path without per-call scoping.

## Cache-then-scan flow
Two-step on every launch:
1. `Stylus_LibraryLoadCache(handle, onCachedTrack, ...)` synchronously fires
   the per-track callback for each entry in `~/Library/Stylus.libcache.json`
   (within the iOS sandbox), so the user sees their library instantly.
2. `Stylus_LibraryStartScan(handle, onScannedTrack, onScanDone, ...)` kicks
   off the background scan. Scanned tracks accumulate in a private
   `scanBuffer`; the cached `tracks` array stays mounted until
   `onScanDone` fires, at which point we atomic-swap. The bridge writes
   `scanBuffer` to the cache file just before firing `onScanDone`, so the
   next launch reads back the freshest snapshot.

The cache key is implicit (folder set match); changing the picked folder
discards the previous cache.

## Per-file scanner timeout
`LibraryScanner::buildTrackInfoWithTimeout` runs `buildTrackInfo` on a
detached worker thread with a 15 s timeout (constant `kPerFileTimeoutMs`).
If a file's metadata read hangs in JUCE's `AudioFormatReader` (malformed
header, broken codec, etc.), the main scanner thread emits a stub
TrackInfo (file path + isPodcast only) and moves on. The detached worker
keeps running until it eventually finishes or the process exits; its
result is discarded. `buildTrackInfo` is `static` for this reason: no
`this` capture means a destroyed scanner can't UAF a still-running worker.

## Scan progress bar
`LibraryStore` runs a parallel pre-count pass on a background queue
(`countAudioFiles(at:)`) that walks the picked folder applying the same
hidden-prefix and supported-extension filter as the desktop scanner. It
publishes `expectedCount` once it lands. The scanner increments
`scannedCount` per delivered track. `LibraryListView` shows a green
`ProgressView(value: scannedCount, total: expectedCount)` while scanning
into an empty library; the bar simply doesn't appear when the cache had
tracks (toolbar spinner is enough).

## Skip-scan optimisation
`LibraryStore.scan(forceFullScan: false)` is the launch path; the
"Re-scan folders" menu item passes `forceFullScan: true`. After
`Stylus_LibraryLoadCache` synchronously repopulates `tracks` from the
on-disk cache, we run `countUniqueAudioFiles(in:)`: a recursive
`FileManager.enumerator` over the music + podcast roots that adds
each canonical path to a `Set<String>`. The Set de-dupes files that
sit under both roots simultaneously (the typical "music folder
contains a Podcasts subfolder" layout, where a sum-of-counts would
double-count). If the de-duped count matches `tracks.count`, the
slow metadata-reading scan (`Stylus_LibraryStartScan`) is skipped
entirely; otherwise we proceed with the full scan.

`countAudioFiles(at:)` (the single-folder version) is still used by
the parallel pre-count pass that drives the scanning progress bar.
