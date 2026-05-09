# Stylus iOS: Architecture Reference

## Overview
SwiftUI + iOS shell over the C++17/JUCE 8.0.4 audio core from the desktop
[Stylus](External/stylus) project, vendored as a git submodule. Architecture
is a thin Objective-C++ bridge that exposes a Swift-callable C facade so the
desktop's library scanner, `.styl` sidecar I/O, BPM / key analysis, and
Apple Music lookup can be reused verbatim. Nothing above the bridge knows
about JUCE; nothing below it knows about Swift / UIKit / SwiftUI.

## Reference material in [docs/](docs/)

Two heavy reference sections live as separate files so this CLAUDE.md
stays focused on architecture / conventions / build:

- [docs/ROADMAP.md](docs/ROADMAP.md) -- phase-by-phase status. Read first
  to confirm the current state; update when finishing a phase.
- [docs/FILES.md](docs/FILES.md) -- annotated source tree. Search here
  first when locating where something lives.

Everything else (build flow, bridge ABI, audio, library, UI patterns) is
inline below.

## Build
Day-to-day: open `StylusApp.xcodeproj` in Xcode, ⌘R. The Xcode project itself
is generated from [project.yml](project.yml) by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and is gitignored. `make` regenerates it; click Revert in Xcode if it's open.

Deployment target is iOS 18 (used `.onScrollGeometryChange` for the
NowPlayingSheet's collapsing artwork; the GeometryReader +
PreferenceKey workaround that's standard on iOS 16/17 didn't fire
reliably on the simulator). Bumped from 16 in 2026-05.

```bash
make           # regenerate StylusApp.xcodeproj from project.yml
make build     # unsigned verification build for iOS device
make build-sim # unsigned verification build for iOS Simulator
make clean     # wipe build/ + build-ios-* CMake build trees
```

A pre-build script phase inside the Xcode project drives CMake to build
`libStylusCore.a` automatically; the script lives inline in [project.yml](project.yml).
You don't need to invoke CMake manually.

### Disk usage (watch `~/Library/Developer/Xcode/DeviceLogs`)
Every device debug-connect session pulls crash dumps + console logs into
`~/Library/Developer/Xcode/DeviceLogs/`. On a heavy debugging day this can
balloon past 10 GB on its own and was the dominant cause of a near-out-of-
disk incident in 2026-05. The directory is purely a transient cache --
deleting its contents is safe and Xcode rebuilds it on demand. Periodic
audit + cleanup:

```bash
du -sh ~/Library/Developer/Xcode/DeviceLogs    # eyeball the size
rm -rf ~/Library/Developer/Xcode/DeviceLogs/*  # wipe; Xcode will repopulate
```

Other dev caches that grow silently and are safe to clear when disk is tight:
`~/Library/Developer/Xcode/iOS DeviceSupport`, `DerivedData`, and the
project's own `build/`, `build-ios-sim/`, `build-ios-device/` (regenerated
by `make build` / `make build-sim`).

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

## Bridge

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

## Library

### Folder picker + security scope
`UIFileSharingEnabled` only bootstraps "On My iPhone" visibility in Files;
the music itself lives outside the sandbox in a user-picked folder
(typically a top-level "On My iPhone" folder, or iCloud Drive / external
drive). `MusicFolderStore` runs `URL.bookmarkData()` after the
`fileImporter` callback and stores the bytes in `UserDefaults`. On launch
it resolves the bookmark and calls `startAccessingSecurityScopedResource()`
once; the scope stays active for the app lifetime so the C++ scanner and
`AVAudioEngine` can read by POSIX path without per-call scoping.

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

### Skip-scan optimisation
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

## Audio

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

`pause()` and `resume()` each call `tickCurrentTime()` at the
transition boundary so `currentTime` reflects the renderer's actual
sample position before the change fires `onPlaybackStateChanged`.
Without this, the timer's last (up to 0.25 s stale) sample is what
NowPlayingController publishes to `MPNowPlayingInfoCenter`, and the
lock-screen seek bar drifts behind real playback by up to a tick
on every pause -- compounding into visible misalignment between the
in-app and lock-screen scrubbers.

### AVAudioSession lifecycle
AudioPlayer registers three notification observers on construction:

- **`interruptionNotification`**: fires on phone calls, alarms, and
  another app activating an exclusive audio session (e.g. Apple
  Music starting). On `.began` we call `pause()` so isPlaying flips
  to false and the lock screen / Control Center stay aligned with
  the silent reality. On `.ended` we resume **only** if the
  notification's options include `.shouldResume` -- some
  interruptions hint that the user wants playback back (phone call
  hung up), others don't (Siri "what's the weather"), and forcing
  a resume against the user's intent is worse than leaving the
  track paused.
- **`routeChangeNotification`**: AirPods unplugged, Bluetooth
  speaker walked out of range, headphone cable yanked. We pause on
  `.oldDeviceUnavailable` only; other reasons (new device added,
  category change) don't need our intervention. Mirrors Apple
  Music's "don't suddenly blast out the phone speaker" behaviour.
- **`mediaServicesWereResetNotification`**: the iOS audio server
  restarted under us (rare but documented). Engine + node refs are
  now stale; we `stop()` and re-`configureSession()` so the next
  `play()` rebuilds cleanly. A surviving track + queue position is
  the user's job to resume.

The session category is `.playback` with mode `.default`: standard
"music app" priority, no speech ducking, no measurement-mode
artefacts. The category isn't reconfigured on the fly.

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
exposes two NSCaches keyed by track file path: `thumbnails` (132 px max,
limit 300) for list rows / transport bar / Up Next, and `largeArt`
(1200 px max, limit 8) for the Now Playing hero artwork and
`MPMediaItemArtwork` on the lock screen. The free async helpers
`loadThumbnail(for:)` and `loadFullArtwork(for:)` route to the right
tier; both decode off the main thread on cache miss.

ImageIO downsampling at decode time (via
`CGImageSourceCreateThumbnailAtIndex` with
`kCGImageSourceThumbnailMaxPixelSize`) keeps 1000 x 1000 album art
JPEGs from being decoded into ~4 MB UIImages just to render at 44 pt
thumbnails; thumb decode lands at ~50 KB. The previous full-resolution
cache was the dominant memory pressure source and the proximate cause
of OOM kills when scrolling Up Next on a long queue.

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

## UI

### NowPlayingSheet sheetY model
RootView owns ONE state variable that drives every visible motion of
the Now Playing sheet:

- `sheetY = 0`        → sheet fully expanded (top edge at top safe-
                        area inset; rounded corners visible above)
- `sheetY = screenH`  → sheet entirely off-screen below; the mini
                        TransportBar at the bottom is the only thing
                        showing.

Both directions of motion write to the same value:

- The TransportBar's lift drag (info-area / drag-handle gestures) reports
  `value.location.y` in `.global` coords; RootView writes
  `sheetY = locationY - safeTop` so the sheet's top tracks the finger
  exactly with no constant delta.
- The sheet's drag-handle `handleDrag` writes
  `sheetY = value.translation.height` so dragging the handle down
  pulls the sheet down 1:1.
- Tap-to-present and the close button just `withAnimation { sheetY = 0 }`
  / `screenH`.

Reading translation in `.global` matters: the host views move with
`sheetY`, so a `.local` gesture would feed back on itself (translation
shrinks as the host shifts, which shrinks sheetY, which un-shifts the
host -- the vertical jitter we hit early on).

`screenH` and `safeTop` are captured by a background `GeometryReader`
on RootView's body and updated on size changes (orientation, etc.).

The tabsLayer underneath has `.allowsHitTesting(sheetY >= screenH - 1)`
so taps in the sheet's rounded-corner cutouts at the top don't fall
through to the navigation bar's back button while the sheet is open.
The gate releases the moment the sheet snaps fully off-screen.

### Sheet presentation is gesture-only
The Now Playing sheet is presented only by explicit user gesture --
tapping the mini transport bar (`onTap` -> `presentSheet()`) or
dragging it up. There is intentionally no scenePhase-based auto-
present: an earlier version watched `@Environment(\.scenePhase)`
and called `presentSheet()` on every transition to `.active`,
hoping that lock-screen / dynamic-island taps would land users in
the full sheet. iOS doesn't expose a signal that distinguishes
"user tapped the now-playing widget" from any other refocus
(Control Center dismissal, return from Apple Music, etc.), so the
heuristic over-presented and felt aggressive. The trade-off is
that a lock-screen widget tap now drops the user at the mini bar
instead of the full sheet; from there they can tap the bar to
expand if they want.

A separate `.onChange(of: scenePhase)` snaps `sheetY` to the
nearest endpoint when the app transitions out of `.active`, so an
in-flight lift drag that got pre-empted by iOS's home-from-bottom
gesture doesn't leave the sheet stuck at a partial position.

### Custom navigation: hidden tab bar + title-menu chevron
The system tab bar is hidden via `.toolbar(.hidden, for: .tabBar)` on
each NavigationStack inside the TabView (the TabView is kept so each
tab's drill-down state, scroll position, and search query survive
flipping tabs from the title-menu chevron). Tab switching is via the
`.tabTitleMenu(_ title:)` modifier in TabNavigation.swift, which adds
a `ToolbarItem(placement: .principal)` containing a UIKit-backed
`UIButton`. The button:

1. Has `showsMenuAsPrimaryAction = true` and a `UIMenu` set ONCE in
   `makeUIView` whose only child is a `UIDeferredMenuElement.uncached`.
2. The deferred element captures the `Coordinator` weakly. When the
   user taps the button, UIKit invokes the deferred element, which
   reads `availableTabs` + `onSelect` from the Coordinator and builds
   a fresh list of `UIAction`s.
3. `updateUIView` only writes the latest props into the Coordinator
   and refreshes the title configuration. **It never reassigns
   `button.menu`.**

This is the workaround for SwiftUI `Menu` lifecycle issues inside
`.toolbar` slots that re-render frequently (during library scan, for
example). A SwiftUI Menu in the same slot got torn down and rebuilt
on every parent re-render -- the visible flicker plus the
"updateVisibleMenuWithBlock while no context menu is visible"
log spam. Same pattern is used for the trailing
`LibraryActionsToolbar` button.

The button writes `tabRouter?.current = tab` inside a
`DispatchQueue.main.async` block so the menu has time to finish its
dismissal animation before the tab actually switches.

### TabRouter: custom env key, not @EnvironmentObject
`TabRouter` is exposed via `.environment(\.tabRouter, router)` and
read via `@Environment(\.tabRouter) var tabRouter: TabRouter?` --
NOT `@EnvironmentObject`. Reading via the custom env key gets us a
class reference we can mutate (`tabRouter?.current = tab`) without
subscribing to its `@Published current`. Subscribing would re-render
every consumer on every tab switch, defeating the
title-menu's UIDeferredMenuElement stability (since the
modifier itself would re-evaluate and rebuild the toolbar item).

RootView still holds the router as a `@StateObject` so the TabView
binds its selection to `$router.current` (binding usage doesn't pull
in @Published subscription either).

### Row taps: Buttons + RowTapButtonStyle, not NavigationLink
Every list row across the app (track rows, group rows for artists /
albums / genres / playlists / podcasts / search hits, plus the My
Library entry rows in HomeView) is a `Button` with
`.buttonStyle(RowTapButtonStyle())` that programmatically appends to
`router.path` rather than a `NavigationLink`. Reasons:

1. NavigationLink in a List on iOS 18+ shows a system grey-on-press
   highlight that manifests as a redundant pre-stage of the long-
   press contextMenu animation -- the same visual clutter the row's
   own ButtonStyle press feedback would add (which is why
   RowTapButtonStyle is haptic-only with no scale / opacity). Using
   Buttons gives us full control over the press visual.
2. NavigationLink + `simultaneousGesture` interacted badly on iOS 18:
   the drag gesture's `.onEnded` fired as a "drag complete" event
   that pre-empted NavigationLink's tap recognizer, so visual
   feedback fired but the navigation never happened.

Buttons hit-test their label's natural shape, which excludes
`Spacer` regions, so every row layout that uses an HStack with a
`Spacer` (LibraryIconRow / CompositeArtworkRow / LibraryDashedRow,
AlbumRow, ArtistRowView / ArtistAlbumRow / AllArtistsAlbumRow,
SearchGroupRow, TrackRow) ends with `.contentShape(Rectangle())` so
the Button wrapper catches taps across the full row width.

### Splash + launch storyboard
Launch sequence:

1. iOS shows `LaunchScreen.storyboard` (image="SplashIcon", 180x180,
   centred on systemBackground). Launch storyboards reject
   `userDefinedRuntimeAttributes`, so the rounded corners are baked
   into `SplashIcon.png` itself: a one-shot Pillow script masks the
   alpha channel with a `rounded_rectangle(radius=205px)` (≈36 pt at
   the 1024-source / 180-display ratio).
2. `SplashView` mounts in SwiftUI, displaying the same icon at the
   same size + corner radius for `1.6 s`, then fades to RootView.
   `.ignoresSafeArea()` is on the ZStack itself (not just the
   background `Color`) so the centre matches the storyboard's
   full-window centring exactly -- otherwise SwiftUI would centre
   within the safe area and the icon would shift down ~30 pt at the
   storyboard → SwiftUI handoff on Dynamic Island devices.
3. RootView is mounted with all environment objects already attached
   at the WindowGroup level. The library scan kicked off in
   `StylusApp.swift`'s `.task` has already loaded the cache (and
   possibly run the skip-scan check) by the time the splash fades,
   so the first list view shows tracks immediately.

`AppIcon.png` is left untouched (square) so the home-screen icon
still gets iOS's normal rounded mask; only `SplashIcon.png` has
baked-in alpha rounding.

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
- Every list-row view (Button, NavigationLink, or any other top-level
  ForEach child) gets `.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }`
  so dividers extend symmetrically. Apply on every row even if it currently
  has no leading icon, so future leading icons don't accidentally shift the
  divider.

## Doc maintenance (mandatory)
Update **the right doc and [README.md](README.md)** in the same commit as a
change that touches:

- Build flow / [project.yml](project.yml) / [CMakeLists.txt](CMakeLists.txt) /
  [Makefile](Makefile) / bridge ABI / architecture / threading / state
  shape / conventions / UI patterns → this CLAUDE.md.
- File responsibilities, new files, renamed files → [docs/FILES.md](docs/FILES.md).
- Roadmap status (mark phases done in the README too) → [docs/ROADMAP.md](docs/ROADMAP.md).

Same commit as the change; never a separate "update docs" follow-up.
The bar for inclusion is "future-Greg or future-Claude would have to read
the diff to understand this." If yes, document it.

This documentation lives in one main file (CLAUDE.md) with two heavy
reference sections split out (FILES, ROADMAP). Keep new architectural
notes in CLAUDE.md alongside the rest, not in fresh per-topic files --
fragmentation makes drift worse and adds round-trips when working across
related areas. Only split out a section when it's both heavy AND reference-
only (consulted, not part of routine architectural reading).

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
3. Every list-row view gets `.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }`
   so the divider extends symmetrically.
4. Row layouts that include a `Spacer` end with `.contentShape(Rectangle())`
   so the entire row width is hit-testable when wrapped in a Button.
5. For navigation: prefer `Button { router?.path.append(value) } label:
   { Row(...) }` with `.buttonStyle(RowTapButtonStyle())` over
   `NavigationLink(value:)` -- keeps row press visuals consistent and
   avoids the iOS 18 NavigationLink + simultaneousGesture interaction.
