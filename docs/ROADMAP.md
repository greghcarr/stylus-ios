# Roadmap

Phase-by-phase status of what's done and what's pending. Update this when
finishing a phase or scoping a new one. Cross-link from the README's high-
level status section.

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
  RowTapButtonStyle drives haptic feedback on press for every
  tappable row across the app (HomeView, TrackRowButton, plus
  the converted group rows in artists / albums / genres /
  playlists / podcasts / search). Earlier scale + opacity press
  visuals were removed because they manifested as a redundant
  pre-stage of the long-press contextMenu animation. Track row
  long-press contextMenu uses `.contentShape(.contextMenuPreview,
  Rectangle())` to match the row's natural shape so the
  anticipation phase visually merges with the row instead of
  drawing a separate inset. Custom `preview:` view with explicit
  padding + `frame(maxWidth: 360)` gives consistent breathing
  room across rows.
- Phase 7a (playlists CRUD + drag-and-drop reorder): done.
  PlaylistStore persists playlists as JSON in
  Library/Application Support/Stylus/playlists.json. Schema
  (id / name / tracks) matches the desktop's
  Stylus::PlaylistStore byte-for-byte so the future sync engine
  just needs to move the file and re-base music-folder paths
  between the two roots. Playlists tab on My Library between
  Genres and Podcasts; PlaylistsView lists existing playlists
  with swipe-to-delete + drag-to-reorder; "Create Playlist"
  lives in the trailing overflow menu. Playlist-DetailView shows
  the playlist's tracks via TrackRowButton, with EditButton-driven
  swipe-delete + drag-reorder that translates between visible-
  track indices and the underlying trackPaths array (so orphaned-
  but-still-stored paths don't shift when the user reorders).
  Trailing menu has Rename Playlist... + Delete Playlist; long-
  press on a playlist row in PlaylistsView gets a fourth
  destructive Delete entry too. Tap any playlist row to drill in;
  tap a track to play from there to the end of the playlist.
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
  pending. See [IOS_PORT_PLAN](../External/stylus/IOS_PORT_PLAN.md).
- Phase X (aspirational): iPad NavigationSplitView + AirPlay +
  general iPad polish, plus CarPlay (gated on Apple's CarPlay
  Audio entitlement). May never ship.
