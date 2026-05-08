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
- Phase 4 (tab navigation: All Songs / Artists / Albums / Genres /
  Podcasts / Search, drill-down): done. RootView wraps everything
  in a single `NavigationStack(path:)` with `HomeView` at the root
  (the "My Library" entry list). Each non-Home tab is a value-based
  `.navigationDestination(for: AppTab.self)` push from HomeView,
  so the user gets iOS's native slide-from-the-right animation.
  `TabRouter` is an ObservableObject that owns the active `AppTab`
  AND the root `NavigationPath`; the path is mutated from
  HomeView's row taps (which are Buttons that call
  `router.path.append(tab)` rather than NavigationLinks -- iOS 18's
  NavigationLink in a List interacts poorly with simultaneous
  gestures attached to the row, so we sidestep the issue with
  programmatic pushes). Each tab gets a shared
  `.libraryActionsToolbar()` modifier for the trailing ellipsis
  menu (Change music folder / Change podcasts folder / Re-scan
  folders), UIKit-backed via `UIDeferredMenuElement` so the menu
  is set ONCE in `makeUIView` and survives the parent's frequent
  re-renders during the library scan (a SwiftUI `Menu` in the
  same slot flickered).
- Phase 5 (background BPM / key analysis): done. The bridged
  `AnalysisEngine` writes the `.styl` sidecar on each track and the
  in-memory library updates as tracks finish so BPM / key appear
  without a rescan. Note: the user-triggered menu entries for
  "Analyse library" / "Look up missing artwork" were removed from the
  trailing toolbar menu in 2026-05; the controllers still exist and
  are still wired into LibraryStore, but no UI currently invokes them.
  Re-add to `LibraryActionsButton.Coordinator.buildMenu` if needed.
- Phase 6a (iTunes Search lookup, library-wide art): done at the
  controller level (LookupController is wired through StylusApp's
  environment objects). The trailing-menu entry that triggered it
  was removed alongside the analyse entry; re-add when reintroducing
  bulk lookup as a user action.
- Phase 6b (Edit Info sheet + per-track context menu): done. Long-press
  a track row to get Play Next / Add to Queue / Look up / Edit Info....
  EditInfoView is a Form-based metadata editor with a "Look up on
  iTunes" button that uses currently-edited fields as the query hint
  and repopulates the form when the result arrives. Save persists via
  `Stylus_StylSave`, which re-loads the existing sidecar first so
  disk-side fields the user didn't edit (playCount, dateAdded, lufs,
  etc.) survive.
- Phase 4.5 (Podcasts folder + tab): done. The trailing overflow menu
  exposes a "Choose podcasts folder…" picker; the bridge takes both
  music and podcast roots and the desktop scanner already excludes
  podcast files from the music scan. The Podcasts tab appears only
  when a podcast folder is set; it lists distinct shows (per
  `track.podcast`) and drills into per-show episodes.
- Phase 6c (skip-scan optimisation): done. After
  `Stylus_LibraryLoadCache` repopulates `tracks` from the on-disk
  cache, `LibraryStore.scan` runs a quick recursive
  `FileManager.enumerator` over the music + podcast roots, de-duped
  via a `Set<String>` keyed by canonical path (so files that sit
  under both roots aren't counted twice -- typical "music/Podcasts"
  layout). If the de-duped count matches `tracks.count`, the slow
  metadata-reading scan is skipped entirely (~50 ms vs. minutes for
  ~1k tracks). The "Re-scan folders" menu calls
  `scan(forceFullScan: true)` to bypass on demand.
- Phase 6d (custom Now Playing presentation): done. Single `sheetY`
  state in RootView drives both directions of motion -- the
  TransportBar's lift drag and the sheet's dismiss drag both write
  to it, finger-tracking via `.global` coordinate-space gestures.
  The full-screen sheet has a collapsing artwork header
  (`scaleEffect(anchor: .top)` + sticky offset, scroll position via
  iOS 18's `.onScrollGeometryChange`). Splash screen + launch
  storyboard for a no-flash launch. Sheet is presented only on
  explicit user gesture (tap the mini transport bar or drag it up);
  no scenePhase-based auto-present, since iOS doesn't expose a
  signal that distinguishes "user tapped the now-playing widget"
  from any other refocus.
- Phase 6e (Genres tab + iTunes-style artist drilldown): done.
  New Genres tab on My Library, listing distinct non-empty genres
  with track counts; tapping a genre drills into its track list.
  ArtistDetailView now branches on the artist's distinct-album
  count: 0 or 1 album skips straight to the track list (no
  busywork album picker), 2+ albums shows "All Albums" first
  followed by each album in alphabetical order, mirroring iTunes'
  classic library navigation. Tapping a specific album pushes
  AlbumDetailView via AlbumKey; tapping All Albums pushes a leaf
  ArtistAllSongsView via the dedicated ArtistAllSongsKey type.
- Phase 6f (audio click fixes): done. Two distinct clicks were
  audible at different track-switch moments. (1) AudioPlayer
  used to call `engine.stop()` between tracks, which made the
  speaker hardware briefly disengage and re-engage on every
  switch (the "click between songs"); now `stopInternal` keeps
  the engine running across the boundary, only tearing it down
  on a full `stop()`. The format reconnect is also skipped when
  the new track has the same sample rate + channel count as the
  previous one (most libraries are mostly 44.1 kHz stereo).
  (2) Manual user switches cut audio mid-amplitude, leaving a
  step discontinuity that clicked; AudioPlayer now ramps the
  player node's volume from current → 0 in 8 sub-steps over
  20 ms before tearing down the schedule on user-initiated
  switches. Auto-advance bypasses the fade since the previous
  track is already at silent end.
- Phase 6g (row tap feedback + context menu polish): done.
  RowTapButtonStyle drives subtle scale + opacity dim + light
  haptic on press for every tappable row across the app
  (HomeView, TrackRowButton). Replaced an earlier
  simultaneousGesture-based modifier that intercepted List's
  scroll recognizer and cancelled NavigationLink taps. Track
  row long-press contextMenu uses `.contentShape(.contextMenuPreview,
  RoundedRectangle(...))` to lock the preview's clipping shape
  so the dismissal animation no longer morphs from rounded to
  square; a custom `preview:` view with explicit padding +
  `frame(maxWidth: 360)` gives consistent breathing room across
  rows in portrait while shrinking gracefully in landscape.
- Phase 7a (playlists CRUD + drag-and-drop reorder): done.
  PlaylistStore persists playlists as JSON in
  Library/Application Support/Stylus/playlists.json. Schema
  (id / name / tracks) matches the desktop's
  Stylus::PlaylistStore byte-for-byte so the future sync engine
  just needs to move the file and re-base music-folder paths
  between the two roots. Playlists tab on My Library between
  Genres and Podcasts; PlaylistsView lists existing playlists
  with swipe-to-delete + drag-to-reorder, "New Playlist" sits
  below the list, native alert prompts for the name with
  contextual pre-fill from the long-press source. Playlist-
  DetailView shows the playlist's tracks via TrackRowButton,
  with EditButton-driven swipe-delete + drag-reorder that
  translates between visible-track indices and the underlying
  trackPaths array (so orphaned-but-still-stored paths don't
  shift when the user reorders). Trailing menu has Rename
  Playlist... + Delete Playlist; long-press on a playlist row
  in PlaylistsView gets a fourth destructive Delete entry too.
  Tap any playlist row to drill in; tap a track to play from
  there to the end of the playlist.
- Phase 7b (group-row "Play Next / Add to Queue / Add to
  Playlist..." context menus): done. New TracksContextMenu
  modifier applied to album rows (AlbumsView + ArtistDetail-
  View albumsList), artist rows, genre rows, podcast show
  rows, and playlist rows. Each call site provides a tracksFor
  closure (lazily evaluated at action time, ordered the way the
  matching detail view orders its tracks) and a suggestedName
  closure that pre-fills the New Playlist alert with the
  group's natural name (album title, artist, etc.). Playlist-
  row variant uses an additionalItems trailing closure to add
  a destructive "Delete Playlist" entry below the standard
  three. PlayQueue gained insertNext([Track]) / append([Track])
  overloads to support batch inserts.
- Phase 7c (scoped overflow menu): done. The trailing
  ellipsis-circle menu's contents are now per-tab: Home shows
  the full set (change music / change-or-choose-or-remove
  podcasts / re-scan), All Songs shows just music + re-scan,
  Podcasts shows just podcasts + re-scan. Artists / Albums /
  Genres / Playlists / Search don't apply
  .libraryActionsToolbar(scope:) at all so the menu icon is
  hidden and inaccessible there. Driven by a LibraryActions-
  Scope enum that the Coordinator switches on in buildMenu().
- Phase 7d (shuffle + repeat in NowPlayingSheet): done. Two
  smaller un-disced glyph buttons flank the three silver
  transport discs in the full-screen sheet's transport row
  (shuffle | prev | play | next | repeat), matching the
  desktop's five-button mod-button-around-discs layout.
  PlayQueue gained shuffle / repeat state machines that mirror
  the desktop byte-for-byte:
  - isShuffled toggle stores originalTracks snapshot, moves
    current track to index 0, Fisher-Yates the rest.
    unshuffle() restores originalTracks whole and places the
    playing track at its original index. setQueue() resets
    shuffle to off (a fresh row-tap is treated as a fresh
    starting point, opt back into shuffle if wanted).
    insertNext / append while shuffled also append to
    originalTracks so a later unshuffle includes them.
  - repeatMode three-state cycle (off / all / one) bound to
    the repeat button's tap. AudioPlayer.handleTrackEnd now
    calls queue.advanceForAutoFinish() instead of advance():
    .one returns currentTrack (replay), .all wraps to index 0
    at end of queue, .off returns nil at end (stop). Manual
    next/prev still uses advance() / goBack() and never wraps
    (matches desktop). Shuffle and repeat tints flip to
    .accentColor when active so the silver discs stay the
    visual anchor of the row.
- Phase 8 (desktop-side sync engine via libimobiledevice):
  pending. See [IOS_PORT_PLAN](External/stylus/IOS_PORT_PLAN.md).
- Phase X (aspirational): iPad NavigationSplitView + AirPlay +
  general iPad polish, plus CarPlay (gated on Apple's CarPlay
  Audio entitlement). May never ship.

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
                              Keeps the engine RUNNING across track
                              switches (the per-track engine.start /
                              engine.stop cycle made the speaker hardware
                              click); only tearing it down on a full stop().
                              User-initiated switches (next / prev / tap
                              another track) pre-fade the player node's
                              volume to 0 over 20 ms in 8 sub-steps to
                              avoid the mid-amplitude cutoff click; the
                              fadeTask is cancelled on a rapid
                              double-tap so the latest press wins. Skips
                              the engine.connect format reconnect when
                              the new track has the same sample rate +
                              channel count as the previous one.
        PlayQueue.swift       Ordered list + currentIndex; advance /
                              goBack / jump / setQueue. Also owns
                              isShuffled + repeatMode state and the
                              originalTracks snapshot needed for
                              shuffleAll / unshuffle / advanceForAuto-
                              Finish. Mirrors the desktop's PlayQueue
                              shuffle/repeat behaviour byte-for-byte.
                              Swift-side, not bridged.
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
        Playlist.swift        Codable struct mirroring the desktop's
                              `Stylus::Playlist` JSON schema (id / name /
                              tracks). Round-trips byte-for-byte across
                              both sides so the future sync engine just
                              moves the file and re-bases music-folder
                              paths.
        PlaylistStore.swift   @MainActor ObservableObject persisting
                              playlists to Library/Application Support/
                              Stylus/playlists.json. CRUD for playlists,
                              add-tracks, reorder both playlists and
                              tracks-within-playlists. nextId derived
                              from max(existing ids) + 1 on load -- no
                              separate on-disk counter to keep in sync.
                              Also exposes migratePathsIfNeeded(against:)
                              which rewrites stored trackPaths whose
                              sandbox-container UUID has changed since
                              the playlist was saved (matches a stale
                              path against the live library by
                              sandbox-relative tail). Called once per
                              launch from StylusApp.swift's .task so
                              playlists.json self-heals after Xcode
                              reinstalls and the like.
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
        RootView.swift        ZStack with the TabView (system tab bar
                              hidden) and the NowPlayingSheet always
                              rendered on top, off-screen via sheetY
                              when the user hasn't lifted it. Owns
                              sheetY (single source of truth for the
                              sheet's vertical position -- 0 = fully
                              expanded, screenH = at the TransportBar).
                              The sheet is shown only by explicit
                              gesture (tap the mini transport bar or
                              drag it up); no scenePhase auto-present.
                              On audio.currentTrack going nil (queue
                              played out), sheetY is reset to screenH
                              so the next song's playback doesn't
                              inherit a stale visible-sheet position. The TransportBar
                              lives below the TabView in a VStack so the
                              system tab bar (when visible) sits ABOVE
                              the bar; currently the system tab bar is
                              hidden via
                              .toolbar(.hidden, for: .tabBar) on each tab.
        SplashView.swift      Initial app surface. Shows the rounded
                              SplashIcon centred on systemBackground for
                              ~1.6 s, then fades to RootView. Matches the
                              LaunchScreen.storyboard exactly so the hand-
                              off from launch chrome to SwiftUI is
                              invisible (no shadow, .ignoresSafeArea on
                              the ZStack so the centre matches the
                              storyboard's full-window centring).
        TabNavigation.swift   AppTab enum (one case per tab),
                              TabRouter ObservableObject (current tab,
                              injected via custom .tabRouter env key NOT
                              .environmentObject so consumers don't
                              subscribe to its @Published), and the
                              .tabTitleMenu(_:) modifier that hangs a
                              UIKit-backed UIButton off the principal
                              toolbar slot. The button uses
                              UIDeferredMenuElement so its UIMenu is set
                              ONCE in makeUIView; updateUIView only
                              writes coordinator state and refreshes the
                              title (avoids the SwiftUI Menu flicker
                              under high-frequency parent re-renders
                              during library scan).
        LibraryActionsToolbar.swift
                              Per-tab trailing overflow menu, scoped via
                              LibraryActionsScope (.home / .music /
                              .podcasts). Home shows the full action set
                              (change music / change-or-choose-or-remove
                              podcasts / re-scan); All Songs and
                              Podcasts show only their tab-relevant
                              subsets. Tabs that should not expose any of
                              these actions (Artists / Albums / Genres /
                              Playlists / Search) simply don't apply
                              the modifier, which keeps the trailing
                              toolbar slot empty -- no menu icon visible.
                              Trailing ellipsis-circle is UIKit-backed
                              via UIDeferredMenuElement so the menu's
                              UIContextMenuInteraction is set ONCE in
                              makeUIView and survives the parent's
                              frequent re-renders during library scan
                              (a SwiftUI Menu in the same slot
                              flickered).
        SilverCircleButtonStyle.swift
                              Silver-gradient ButtonStyle used by every
                              transport button (mini and full sheet) to
                              match the desktop's transport disc and the
                              app icon's metallic silver tone. Caller
                              picks the diameter; foregroundStyle(.black)
                              is forced inside so SF-Symbol glyphs
                              render black against the silver.
        LibraryListView.swift All Songs tab content (renamed from Library
                              -- AppTab.library.title is "All Songs").
                              Three states: pick-folder, scanning-with-
                              progress-bar, populated list. Keeps a
                              minimal showMusicPicker @State for the
                              empty-state "Choose Music Folder…" button;
                              the trailing menu's "Change music folder…"
                              has its own picker via the shared
                              .libraryActionsToolbar() modifier.
        HomeView.swift        My Library entry list. Each row is a
                              Button (NOT a NavigationLink) that
                              programmatically appends an AppTab to
                              the root NavigationPath via the shared
                              TabRouter -- avoids an iOS 18
                              NavigationLink-vs-simultaneousGesture
                              interaction that swallowed taps when
                              gesture-based row feedback was attached.
        ArtistsView.swift     Artists tab + ArtistDetailView +
                              ArtistAllSongsView. ArtistDetailView
                              branches on the artist's distinct-album
                              count: 0 or 1 album drops straight to
                              the track list, 2+ shows "All Albums" +
                              alphabetised album rows (iTunes-style).
                              ArtistAllSongsKey is a typed wrapper
                              that distinguishes "all songs by artist"
                              from individual AlbumKey pushes.
        AlbumsView.swift      Albums tab + AlbumDetailView, with a
                              representative-track artwork thumbnail.
                              AlbumKey identifies an album by
                              (artist, album); ArtistDetailView pushes
                              AlbumKey too and registers its own
                              navigationDestination locally.
        GenresView.swift      Genres tab + GenreDetailView. Lists
                              distinct non-empty genre names with
                              track counts; GenreKey wraps the genre
                              name as a typed nav value.
        PlaylistsView.swift   Playlists tab + PlaylistDetailView +
                              AddToPlaylistSheet + PlaylistKey nav
                              wrapper. Top-level lists existing
                              playlists (swipe-to-delete + drag-to-
                              reorder + long-press for "Delete
                              Playlist"); New Playlist row sits at
                              the bottom of the list. Detail view
                              renders the playlist's resolved tracks
                              via TrackRowButton, with edit-mode
                              drag-reorder that translates visible
                              indices back to the underlying
                              trackPaths array so orphans stay put.
                              AddToPlaylistSheet takes [Track] (with
                              a single-Track convenience init) and a
                              suggestedName for the New Playlist
                              prefill.
        TracksContextMenu.swift
                              .tracksContextMenu(suggestedName:
                              tracksFor: preview:) modifier providing
                              "Play Next / Add to Queue / Add to
                              Playlist..." long-press actions on any
                              row that represents a track group
                              (album, artist, genre, podcast,
                              playlist). Required preview: ViewBuilder
                              gives every group row the same long-
                              press preview shape (rounded rectangle,
                              padded, frame(maxWidth: 360)) so the
                              dismissal animation no longer morphs
                              from rounded to square -- matches the
                              parity TrackRowButton already had.
                              Optional additionalItems ViewBuilder
                              for per-callsite extras (playlist rows
                              add the destructive Delete entry).
        CompositeArtworkThumb.swift
                              44 x 44 thumbnail that renders 0 / 1 /
                              2x2 grid of album thumbs depending on
                              how many of the supplied
                              representativePaths produce artwork.
                              Used by every "group of tracks" row
                              (artists, genres, playlists, podcasts).
                              Empty grid slots are transparent so the
                              row's natural background shows through.
                              Empty-state branch + the per-app
                              "(no X)" rows share the same
                              DashedSquarePlaceholder (defined here)
                              so every "no value for this category"
                              glyph in the app looks identical.
        LibraryIconRow.swift  Three shared row shapes for "All X" /
                              per-X / "(no X)" sentinels, factored
                              out of the per-tab views: LibraryIconRow
                              (SF-Symbol icon + title + count for
                              All X), CompositeArtworkRow (composite
                              2x2 thumb + title + count for per-X),
                              LibraryDashedRow (dashed-square
                              placeholder + italic title + count for
                              "(no X)"). Sharing the row shapes also
                              lets each tab pass the same view as
                              long-press preview: closure for parity.
        PodcastsView.swift    Podcasts tab + PodcastDetailView, grouped
                              by track.podcast.
        SearchView.swift      Search tab. .searchable matches across
                              tracks, artists, albums, podcasts,
                              podcast episodes, and playlists; results
                              render in fixed-order Sections per type
                              and each row's second line is the
                              category label (Track / Artist / Album /
                              Podcast / Podcast episode / Playlist).
                              Track rows render as "Artist - Title"
                              via titleOverride. Group rows push typed
                              nav values (SearchArtistKey /
                              SearchPodcastKey wrap String, AlbumKey +
                              PlaylistKey reused) so the local
                              .navigationDestination registrations
                              don't collide with the parent stack's
                              String-keyed routes. The "Search your
                              library" prompt is suppressed while
                              @Environment(\.isSearching) is true (so
                              the prompt doesn't shout at the user
                              from beneath the keyboard); it returns
                              the moment the user dismisses search.
        TrackRow.swift        Pure-presentation row used by every track
                              list (All Songs, Artist, Album, Podcast,
                              Search). Speaker glyph next to the title
                              indicates the currently-playing track.
                              Optional titleOverride / subtitleOverride
                              replace the standard track.displayTitle +
                              "artist - album" subtitle; SearchView
                              passes "Artist - Title" + "Track" /
                              "Podcast episode" so each search row
                              announces what kind of result it is.
        TrackRowButton.swift  Button wrapper that, on tap, sets the queue
                              to the visible-track slice and starts
                              playback at the tapped row. Long-press
                              .contextMenu surfaces Play Next /
                              Add to Queue / Look up / Edit Info....
                              Uses .contentShape(.contextMenuPreview,
                              RoundedRectangle(...)) to lock the
                              preview's clipping shape (so dismissal
                              doesn't morph rounded -> square) plus
                              a custom preview: view at frame(maxWidth:
                              360) for consistent breathing room
                              across rows in portrait and graceful
                              shrink in landscape. Owns the .sheet
                              that hosts EditInfoView.
                              .alignmentGuide(.listRowSeparatorLeading)
                              pins the row separator to the cell's
                              leading edge (matches album-art left).
                              Forwards optional titleOverride +
                              subtitleOverride to TrackRow + the
                              long-press preview's TrackRow (used by
                              SearchView).
        RowTapFeedback.swift  RowTapButtonStyle: ButtonStyle with the
                              row press visuals (scale 0.97 + opacity
                              0.65) and a light haptic on press-down.
                              Animation is asymmetric -- ease into
                              pressed, instant snap back on release --
                              so when the contextMenu is up and the
                              system later flips isPressed to false,
                              the row doesn't visibly rebound.
        HapticFeedback.swift  Shared UIImpactFeedbackGenerator wrapper.
                              Single long-lived instance for tapTick(),
                              avoiding per-tap allocation. We
                              deliberately do NOT call .prepare() at
                              app launch: the haptic engine
                              auto-deactivates after ~3 s and logs
                              "Player was not running" / "core haptics
                              engine finished with error" on
                              deactivation, which spammed the console.
                              First-call latency without prepare is
                              barely perceptible.
        ListFirstRowSeparator.swift
                              .hideFirstRowSeparator(_:) helper that
                              hides the top edge of the first row in
                              a List. Apply inside an enumerated
                              ForEach with index == 0; suppresses the
                              top divider plain List would otherwise
                              draw. .listSectionSeparator(.hidden)
                              alone doesn't reliably handle this on
                              iOS 26.
        TransportBarBottomSpacer.swift
                              Trailing footer row for any List of
                              songs. Reserves transport-bar clearance
                              when a track is playing AND
                              unconditionally suppresses the divider
                              under the actual last song row via
                              .listRowSeparator(.hidden). Renders at
                              0 height + 0 insets when no track is
                              current so it takes no visible space
                              but still suppresses the trailing
                              divider.
        EditInfoView.swift    Per-track metadata editor (Form). "Look up
                              on iTunes" kicks LookupController.enqueue
                              with the currently-edited fields; .onChange
                              on library.tracks repopulates the form when
                              the result lands. Save calls
                              LibraryStore.save which round-trips through
                              Stylus_StylSave (load-then-overwrite-then-
                              save preserves untouched disk fields).
        EmptyStateView.swift  Centred empty-state block (icon + title +
                              optional message), used by Search and the
                              other tabs when their list is empty.
        TransportBar.swift    Bottom mini-player. Sticky drag handle at
                              the top (white-on-grab feedback, location-
                              based DragGesture in .global so the host's
                              own offset doesn't feed back into the
                              translation). Album art with a radial
                              "played pie" veil that sweeps clockwise
                              from 12 o'clock through the played
                              fraction. Title block + small
                              SilverCircleButtonStyle play/pause and
                              skip on the right edge. Tap the info area
                              or drag the handle up to lift the
                              NowPlayingSheet (writes RootView's
                              sheetY directly via the lift-drag
                              callbacks).
        NowPlayingSheet.swift Full-screen sheet: drag handle (sticky,
                              outside the ScrollView) + ScrollView
                              containing the artwork (with a collapsing-
                              header treatment via .scaleEffect(.top) +
                              sticky offset that pins the top of the art
                              to the visible scroll-top while it shrinks
                              to ¼ size, then scrolls normally) + title
                              + scrubber + transport + Up Next. Sheet
                              background is .secondarySystemBackground in
                              an UnevenRoundedRectangle with 24-pt top
                              corners; .ignoresSafeArea(edges: .bottom)
                              so the sheet stops below the top safe-area
                              inset and the system status bar renders
                              over the underlying tab. Auto-scrolls to
                              "npTop" on .onAppear so re-mounting the
                              sheet (tap or drag-up) starts at the
                              artwork.
        CircleSlider.swift    Circle-thumbed scrubber. DragGesture is
                              attached ONLY to the thumb itself (not the
                              track) so tapping somewhere on the bar
                              doesn't jump the thumb -- the user must
                              grab and drag. Uses translation +
                              captured-at-start initialValue to avoid
                              compounding drift from reading the live
                              (mutating) value.
      Resources/
        Info.plist            UIFileSharingEnabled (for On My iPhone surface),
                              LSSupportsOpeningDocumentsInPlace,
                              UIBackgroundModes=[audio],
                              UILaunchStoryboardName=LaunchScreen.
        LaunchScreen.storyboard
                              Launch storyboard. Centred 180x180
                              UIImageView with image=SplashIcon, on a
                              systemBackground root view. Rounded
                              corners are NOT set as a runtime
                              attribute (launch screens reject those);
                              they're baked into SplashIcon.png itself
                              as transparent alpha.
        Assets.xcassets       AppIcon (square 1024x1024 -- iOS rounds
                              the home-screen icon for us) and
                              SplashIcon (a copy of the icon with
                              rounded corners baked into the alpha
                              channel via a one-shot Pillow script for
                              the launch screen + SwiftUI splash).
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
- Every list-row view (NavigationLink, Button, or any other top-level
  ForEach child) gets `.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }`.
  The user wants horizontal dividers to extend symmetrically -- the same
  distance from the left edge as from the right -- and SwiftUI's default
  pins the leading separator inset to wherever the row content begins,
  which leaves a visible gap on the left when the row has a leading icon
  or padding. The pin defeats that default. Apply the modifier on every
  row even if the row currently has no leading icon, so future leading
  icons don't accidentally shift the divider.

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
