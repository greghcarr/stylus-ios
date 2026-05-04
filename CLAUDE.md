# Stylus iOS: Architecture Reference

## Overview
SwiftUI + iOS shell over the C++17/JUCE 8.0.4 audio core from the desktop
[Stylus](External/stylus) project, vendored as a git submodule. Architecture
is a thin Objective-C++ bridge that exposes a Swift-callable C facade so the
desktop's library scanner, `.styl` sidecar I/O, BPM / key analysis, and
Apple Music lookup can be reused verbatim. Nothing above the bridge knows
about JUCE; nothing below it knows about Swift / UIKit / SwiftUI.

## Roadmap status (as of this CLAUDE.md update)
- Phase 0 (desktop core extraction): done (commit `e0a4e82` in the stylus repo).
- Phase 1 (bridge + SwiftUI list + tap-to-play `AVAudioPlayer`): done.
- Phase 1.5 (folder picker + security-scoped bookmark): done.
- Phase 1.6 (`LibraryCache` bridged for instant launches): done.
- Phase 1.7 (per-file scanner timeout, smaller batch size): done.
- Phase 2 (album art + full `.styl` metadata in row): done. Track row shows
  thumbnail + bpm + musical key alongside title/artist/album/duration.
- Phase 3a (Swift PlayQueue, AVAudioEngine-based AudioPlayer, bottom
  TransportBar, auto-advance): done. Tap a row to queue from there to end
  of view; transport bar pinned above the safe area.
- Phase 3b (full-screen Now Playing sheet): done. Tap the bar's art / title
  region to lift a sheet with large art, scrubber, and big transport.
- Phase 3c (MPNowPlayingInfoCenter + remote commands + lock-screen art):
  done. Lock screen, Control Center, and AirPods controls drive playback;
  artwork shows on the lock screen.
- Phase 4 (tab bar with Library / Artists / Albums / Search,
  drill-down): done. RootView owns the TabView, the persistent
  TransportBar via `.safeAreaInset(.bottom)`, and the NowPlayingSheet
  presentation, so every tab gets the same chrome.
- Phase 5 (background BPM / key analysis): done. User-triggered via the
  Library tab's overflow menu; the bridged `AnalysisEngine` writes the
  `.styl` sidecar on each track and the in-memory library updates as
  tracks finish so BPM / key appear without a rescan.
- Phase 6a (iTunes Search lookup, library-wide art): done. Library tab
  overflow has "Look up missing artwork"; the bridged `AppleMusicLookup`
  writes `.styl-art.jpg` per track and `ArtworkCache.invalidate(for:)`
  drops the stale cache entry so the next decode picks up the new file.
- Phase 6b (Edit Info sheet + per-track context menu): done. Long-press
  a track row to get Play Next / Add to Queue / Look up / Edit Info....
  EditInfoView is a Form-based metadata editor with a "Look up on
  iTunes" button that uses currently-edited fields as the query hint
  and repopulates the form when the result arrives. Save persists via
  `Stylus_StylSave`, which re-loads the existing sidecar first so
  disk-side fields the user didn't edit (playCount, dateAdded, lufs,
  etc.) survive.
- Phase 7+ (playlists, polish):
  pending. See [IOS_PORT_PLAN](External/stylus/IOS_PORT_PLAN.md).

## Build
Day-to-day: open `StylusApp.xcodeproj` in Xcode, ⌘R. The Xcode project itself
is generated from [project.yml](project.yml) by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and is gitignored. `make` regenerates it; click Revert in Xcode if it's open.

```bash
make           # regenerate StylusApp.xcodeproj from project.yml
make build     # unsigned verification build for iOS device
make build-sim # unsigned verification build for iOS Simulator
make clean     # wipe build/ + build-ios-* CMake build trees
```

A pre-build script phase inside the Xcode project drives CMake to build
`libStylusCore.a` automatically; the script lives inline in [project.yml](project.yml).
You don't need to invoke CMake manually.

## File layout
```
stylus-ios/
  CMakeLists.txt              StylusCore static lib (shared with desktop +
                              the bridge .mm), one CMake target only.
  project.yml                 XcodeGen config for StylusApp.xcodeproj.
  Makefile                    Convenience targets (make / build / clean).
  External/stylus/            git submodule -> github.com/greghcarr/stylus.
                              C++ core (audio/, analysis/, library/) vendored
                              verbatim. Updates only via deliberate pin bumps.
  Sources/
    StylusBridge/
      StylusBridge.h          C-only header used as Swift-Objective-C bridging
                              header. extern "C" facade for the C++ core.
      StylusBridge.mm         Objective-C++ implementation. Compiled INTO
                              libStylusCore.a, not as its own static lib (see
                              "JUCE INTERFACE-link gotcha" below).
    StylusApp/
      StylusApp.swift         App entry. Calls Stylus_Initialize() once.
                              Constructs PlayQueue + AudioPlayer wired to it.
      Audio/
        AudioPlayer.swift     AVAudioEngine + AVAudioPlayerNode. Auto-advances
                              through the attached PlayQueue on track end;
                              exposes currentTime / duration / isPlaying.
                              Calls onPlaybackStateChanged after every play /
                              pause / resume / stop / seek so external
                              listeners (NowPlayingController) can refresh.
        PlayQueue.swift       Ordered list + currentIndex; advance / goBack /
                              jump / setQueue. Swift-side, not bridged.
        NowPlayingController.swift Bridges AudioPlayer state to
                              MPNowPlayingInfoCenter + registers
                              MPRemoteCommandCenter handlers. Lock-screen,
                              Control Center, AirPods, future CarPlay all
                              drive the same playback.
      Library/
        Track.swift           Swift value type bridging from StylusTrackC.
        LibraryStore.swift    ObservableObject. Owns the C library handle,
                              cache-then-scan flow, scan progress counters.
                              updateTrack(_:) is called by AnalysisController
                              to refresh BPM / key in-place without a rescan.
        MusicFolderStore.swift Holds the user-picked music folder URL,
                              persists it as a security-scoped bookmark.
        ArtworkCache.swift    NSCache of decoded UIImage keyed by file path,
                              plus an async loadArtwork(for:) helper that
                              calls Stylus_ExtractArtwork off the main thread.
        AnalysisController.swift Drives the bridged AnalysisEngine. Queues
                              tracks the user requested for analysis,
                              exposes queueDepth + isAnalysing, and pushes
                              freshly-analysed tracks back into LibraryStore
                              via updateTrack on the main thread.
        LookupController.swift Drives the bridged AppleMusicLookup. Same
                              shape as AnalysisController; on completion
                              calls ArtworkCache.invalidate(for:) so the
                              row's next decode pass picks up the new
                              .styl-art.jpg sidecar.
      UI/
        RootView.swift        TabView with Library / Artists / Albums /
                              Search; pins TransportBar via
                              .safeAreaInset(.bottom); owns the
                              NowPlayingSheet presentation.
        LibraryListView.swift Library tab content: three states
                              (pick-folder, scanning-with-progress-bar,
                              populated list). NavigationStack is owned by
                              RootView, not here.
        ArtistsView.swift     Artists tab + ArtistDetailView.
        AlbumsView.swift      Albums tab + AlbumDetailView, with a
                              representative-track artwork thumbnail.
        SearchView.swift      Search tab; .searchable filters tracks by
                              title / artist / album live.
        TrackRow.swift        Pure-presentation row used by every track
                              list (Library, Artist, Album, Search).
        TrackRowButton.swift  Button wrapper that, on tap, sets the queue
                              to the visible-track slice and starts
                              playback at the tapped row. Long-press
                              .contextMenu surfaces Play Next /
                              Add to Queue / Look up / Edit Info.... Owns
                              the .sheet that hosts EditInfoView.
        EditInfoView.swift    Per-track metadata editor (Form). "Look up
                              on iTunes" kicks LookupController.enqueue
                              with the currently-edited fields; .onChange
                              on library.tracks repopulates the form when
                              the result lands. Save calls
                              LibraryStore.save which round-trips through
                              Stylus_StylSave (load-then-overwrite-then-
                              save preserves untouched disk fields).
        EmptyStateView.swift  iOS-16-compatible stand-in for SwiftUI 17's
                              ContentUnavailableView.
        TransportBar.swift    Bottom strip with art / title / play-pause /
                              next. Tappable art+title region calls the
                              onTap closure (parent presents the sheet).
                              Hidden when nothing is current.
        NowPlayingSheet.swift Full-screen sheet: large art + title + scrubber
                              + big transport. Scrubber uses a local @State
                              that mirrors audio.currentTime when not being
                              dragged, so user scrubbing doesn't fight with
                              the 0.25 s currentTime ticker.
        CircleSlider.swift    Circle-thumbed scrubber used in the Now
                              Playing sheet; thumb / track / shadow spring
                              up while dragging.
      Resources/
        Info.plist            UIFileSharingEnabled (for On My iPhone surface),
                              LSSupportsOpeningDocumentsInPlace,
                              UIBackgroundModes=[audio].
        Assets.xcassets       AppIcon (full-bleed iOS variant generated by
                              External/stylus/resources/make_app_icon.py).
```

## Key patterns

### Bridge ABI
`StylusBridge.h` is a plain-C header used as the Swift-Objective-C bridging
header (`SWIFT_OBJC_BRIDGING_HEADER` in [project.yml](project.yml)). All
`Stylus_*` symbols and `StylusTrackC` are visible to Swift directly without
`import StylusBridge` or a modulemap.

The library handle is an opaque pointer:
```c
typedef struct StylusLibrary StylusLibrary;
typedef StylusLibrary* StylusLibraryHandle;
```
which Swift imports as `OpaquePointer`. The full struct definition lives in
the .mm at namespace scope so the tag matches across the C / C++ boundary.
Callbacks pass `void* userData`, which Swift fills with
`Unmanaged<LibraryStore>.passUnretained(self).toOpaque()` so the C function
can recover the Swift instance.

`StylusTrackC.const char*` fields point to UTF-8 storage owned by a local
`TrackBytes` instance for the duration of the callback. Callers must copy
what they keep; the strings die when the callback returns.

### JUCE INTERFACE-link gotcha
JUCE 8's `juce_add_module` attaches sources via INTERFACE properties, so
every consumer that links a JUCE module compiles its own copy. If
`StylusBridge` were its own static lib that linked `juce::juce_*`, the app
would see duplicate symbols at link time. Solution: the bridge .mm is
compiled into the same `StylusCore` target as the rest of the C++ core, so
there's exactly one set of JUCE objects in the output `libStylusCore.a`.
Do not split it into a second static lib.

### JUCE message thread on iOS
`Stylus_Initialize()` calls `juce::initialiseJuce_GUI()` once from the main
thread (lazy via `std::call_once`). That installs JUCE's CFRunLoopSource
on the main run loop so `juce::MessageManager::callAsync(...)` from JUCE's
background scanner thread is delivered as a main-thread tick to our
callbacks. Always call `Stylus_Initialize()` from the SwiftUI App's `init`
or before any other `Stylus_*` call.

### Folder picker + security scope
`UIFileSharingEnabled` only bootstraps "On My iPhone" visibility in Files;
the music itself lives outside the sandbox in a user-picked folder
(typically a top-level "On My iPhone" folder, or iCloud Drive / external
drive). `MusicFolderStore` runs `URL.bookmarkData()` after the
`fileImporter` callback and stores the bytes in `UserDefaults`. On launch
it resolves the bookmark and calls `startAccessingSecurityScopedResource()`
once; the scope stays active for the app lifetime so the C++ scanner and
`AVAudioPlayer` can read by POSIX path without per-call scoping.

### Cache-then-scan flow
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

### Audio engine choice
Picked `AVAudioEngine` + `AVAudioPlayerNode` over `AVAudioPlayer` because
the eventual roadmap (DJ mode: gapless, level meters, EQ / pitch-shift,
two-deck mixing) all needs the engine graph. `AVAudioPlayer` doesn't scale
into any of that; the upgrade later would be a rewrite. `AVAudioEngine`
costs ~30 extra lines in [AudioPlayer.swift](Sources/StylusApp/Audio/AudioPlayer.swift)
and we get the foundation for free.

Per-track playback flow:
1. `play(_ track)` opens `AVAudioFile`, captures `processingFormat`,
   `length`, and `sampleRate`.
2. `engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)`
   reconnects with each track's native format so the mixer downmixes /
   resamples to the output device. (Files with different formats can
   follow each other without engine.stop() because we re-connect.)
3. `node.scheduleSegment(..., completionCallbackType: .dataPlayedBack)`
   schedules the entire file from `seekFrame` and registers a completion
   handler that bounces onto MainActor and calls `playNext()`.
4. `engine.start()` if needed, `node.play()`.

`currentTime` is computed on a 0.25 s `Timer` from
`node.playerTime(forNodeTime:lastRenderTime)` plus the current
`seekFrame` offset. Seeks `node.stop()` + `scheduleSegment` from the new
frame so `lastRenderTime` resets and the offset arithmetic stays right.
Pause keeps the buffer scheduled, so `node.play()` resumes seamlessly
without rescheduling.

### Now Playing center + remote commands
[NowPlayingController.swift](Sources/StylusApp/Audio/NowPlayingController.swift)
is constructed once in [StylusApp.swift](Sources/StylusApp/StylusApp.swift)
with a reference to the `AudioPlayer`. It hooks
`AudioPlayer.onPlaybackStateChanged` (a single closure, not Combine, so
there's only one source of truth for "something playback-relevant
happened") and on every fire writes a fresh
`MPNowPlayingInfoCenter.default().nowPlayingInfo` dictionary with title /
artist / album / duration / elapsed / rate. Once track-changes happen,
it kicks an async `loadArtwork(for:)` off the cache and merges
`MPMediaItemArtwork` into the info dict. If the artwork is already in
the cache (typical when the user just looked at the row), it's attached
synchronously to avoid the lock-screen "no art then art" flicker.

We don't push on every `currentTime` tick: the system extrapolates
elapsed from the last (elapsed, rate) pair we set, so play / pause /
seek transitions are sufficient.

The same controller registers `MPRemoteCommandCenter` handlers
(play / pause / togglePlayPause / next / prev / changePlaybackPosition)
that route into `AudioPlayer`, so lock-screen, Control Center, AirPods,
and (eventually, Phase X) CarPlay all drive the same audio engine.

### Album art loading
[Sources/StylusApp/Library/ArtworkCache.swift](Sources/StylusApp/Library/ArtworkCache.swift)
exposes a `MainActor`-isolated `ArtworkCache` (singleton, `NSCache` of
`UIImage` keyed by track file path, count limit 200) plus a free async
`loadArtwork(for:)` that decodes off the main thread on cache miss.

The lookup chain mirrors the desktop's
[AlbumArtExtractor.cpp](External/stylus/src/audio/AlbumArtExtractor.cpp),
re-implemented in Swift because the desktop's `juce::Image`-returning
function lives in juce_graphics which isn't linked on iOS:

1. **Embedded artwork**: bridge functions
   `Stylus_ExtractArtwork` / `Stylus_FreeArtworkBytes` return malloc'd
   JPEG / PNG bytes via the desktop's
   [AlbumArtExtractor.mm](External/stylus/src/audio/AlbumArtExtractor.mm)
   (AVFoundation `commonMetadata` query).
2. **Per-track sidecar**: `.<filename>.styl-art.jpg` next to the audio
   file (written by the desktop's Apple Music lookup task).
3. **Folder-level art**: `cover / folder / artwork / album / front`
   with extensions `jpg / jpeg / png` in the audio file's parent
   directory. APFS is case-insensitive so we don't enumerate case
   variants.

Each `TrackRow` runs its own
`.task(id: filePath) { artwork = await loadArtwork(for: filePath) }`,
which is fine because SwiftUI's `List` virtualises and only visible rows
fire their task. Cache hits short-circuit the detached work entirely so
scrolling back is instant.

`Stylus_ExtractArtwork` is a thin wrapper around the existing desktop
`Stylus_extractEmbeddedArtwork`. We forward-declare that function in
[StylusBridge.mm](Sources/StylusBridge/StylusBridge.mm) rather than
include a header, because the desktop intentionally leaves
`AlbumArtExtractor.mm` JUCE-free so the .mm and the JUCE-flavoured .cpp
wrapper can coexist without translation-unit conflicts (the JUCE Carbon
`Point` / `Component` types collide with AVFoundation's).

### Per-file scanner timeout
`LibraryScanner::buildTrackInfoWithTimeout` runs `buildTrackInfo` on a
detached worker thread with a 15 s timeout (constant `kPerFileTimeoutMs`).
If a file's metadata read hangs in JUCE's `AudioFormatReader` (malformed
header, broken codec, etc.), the main scanner thread emits a stub
TrackInfo (file path + isPodcast only) and moves on. The detached worker
keeps running until it eventually finishes or the process exits; its
result is discarded. `buildTrackInfo` is `static` for this reason: no
`this` capture means a destroyed scanner can't UAF a still-running worker.

### Scan progress bar
`LibraryStore` runs a parallel pre-count pass on a background queue
(`countAudioFiles(at:)`) that walks the picked folder applying the same
hidden-prefix and supported-extension filter as the desktop scanner. It
publishes `expectedCount` once it lands. The scanner increments
`scannedCount` per delivered track. `LibraryListView` shows a green
`ProgressView(value: scannedCount, total: expectedCount)` while scanning
into an empty library; the bar simply doesn't appear when the cache had
tracks (toolbar spinner is enough).

### CMake script-phase environment
The pre-build script in [project.yml](project.yml) clears its environment
with `env -i` before invoking CMake. This is necessary because Xcode injects
`SDKROOT=iphoneos26.4`, `SDK_DIR`, `TOOLCHAINS`, etc., which leak into the
recursive `cmake` call JUCE makes to bootstrap `juceaide` for the host. The
host bootstrap needs the macOS SDK; without sanitisation it fails compiler
detection. The script also restores `DEVELOPER_DIR` from `xcode-select -p`
so the tools are still findable.

### CMake script-phase fast path
The same script in [project.yml](project.yml) does an mtime-based freshness
check before calling CMake: if `libStylusCore.a` exists and no input under
`Sources/StylusBridge/`, `External/stylus/src/`, or `CMakeLists.txt` is
newer than the lib, it `exit 0`s before invoking cmake at all. This drops
a no-op script-phase invocation from ~6 s to ~1.3 s and is the difference
between "5-10 s ⌘R" and "10-20 s ⌘R" for Swift-only iterations.

If you change CMake-side build options (e.g. add a new source to the cmake
target's source list, or change `-DCMAKE_*` flags), `make clean` once to
force the slow path; the fast path doesn't watch project-config files.

### Submodule update workflow
The desktop submodule is pinned to a specific commit. It does not auto-update.
Bump the pin only when iOS work needs new desktop changes:
```sh
cd External/stylus && git pull origin master  # or work directly in submodule
cd ../..
git add External/stylus
git commit -m "Bump stylus submodule: <reason>"
```
Avoid bumping in isolation; bundle the bump with the iOS work that needs it
so regressions are easy to attribute via `git bisect`.

## Conventions
- No em-dashes or en-dashes anywhere (per global CLAUDE.md). Plain hyphens
  for separators.
- `DEVELOPMENT_TEAM` lives in `project.yml` so it survives `xcodegen`
  regenerations. Personal-team Apple ID's team ID is what goes here.
- File references in Markdown use the relative path link form, not backticks.
- Don't add `UIFileSharingEnabled` back to expose Documents in Files unless
  Documents has something useful in it. Currently it's just there as a
  workaround so "On My iPhone" appears as a Files-app surface.
- The CMake target generates the inner `StylusIOS.xcodeproj` but that's a
  build artifact. The user-facing project is `StylusApp.xcodeproj` which is
  XcodeGen-driven.

## Doc maintenance (mandatory)
Update **this file and [README.md](README.md)** whenever a change touches:

- Build flow, script-phase logic, [project.yml](project.yml), [CMakeLists.txt](CMakeLists.txt),
  or the [Makefile](Makefile).
- The bridge ABI ([Sources/StylusBridge/StylusBridge.h](Sources/StylusBridge/StylusBridge.h))
  or how Swift calls into it.
- Architecture ownership / threading / state shape (e.g. who owns the
  security scope, who owns the cache, how the scanner is driven).
- Conventions, tooling, or the developer workflow.
- Roadmap status (mark phases done in the README; add new phase notes here).

Same commit as the change; never a separate "update docs" follow-up.
The bar for inclusion is "future-Greg or future-Claude would have to read
the diff to understand this." If yes, document it.

## Adding a new bridge function checklist
1. Add the C declaration to `Sources/StylusBridge/StylusBridge.h` inside
   `extern "C"`. Use `int32_t` / `int64_t` over `int` / `long` for ABI
   stability across Swift / Obj-C bridging.
2. Implement in `Sources/StylusBridge/StylusBridge.mm`. Marshal `juce::String`
   via `toStdString()` into a TrackBytes-equivalent owner struct so the
   `const char*` fields outlive the callback.
3. If the function is called from a callback that must run on the main
   thread, wrap your dispatch in `juce::MessageManager::callAsync`.
4. Add the Swift call site in `LibraryStore.swift` (or wherever fits).
   Bridge `void* userData` via `Unmanaged.passUnretained(self).toOpaque()`.
5. No `make regen` is needed for header / .mm changes; just build.

## Adding a new SwiftUI view checklist
1. New file under `Sources/StylusApp/UI/`. Use `@EnvironmentObject` for the
   stores rather than direct refs.
2. No `make regen` needed; XcodeGen's `path: Sources/StylusApp` glob picks
   up new files on next regen, but Xcode's own file watcher catches them
   without regenerating in most cases.
