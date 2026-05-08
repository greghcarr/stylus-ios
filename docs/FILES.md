# File layout

Annotated tree of every project source file with its responsibility.
Search here first when locating where something lives. Update entries
when files are added, renamed, or change responsibility.

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
                              BRIDGE.md "JUCE INTERFACE-link gotcha").
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
                              inherit a stale visible-sheet position.
                              tabsLayer's .allowsHitTesting is gated
                              by sheetY so taps in the sheet's rounded-
                              corner cutouts don't fall through to the
                              underlying nav-bar back button.
                              The TransportBar lives below the TabView
                              in a VStack so the system tab bar (when
                              visible) sits ABOVE the bar; currently the
                              system tab bar is hidden via
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
                              The same Button-with-router.path.append
                              pattern is now used by every group-row
                              call site in artists / albums / genres /
                              playlists / podcasts / search so they
                              all use RowTapButtonStyle's haptic-only
                              feedback instead of the system list-row
                              grey-on-press highlight.
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
                              Playlist"); "Create Playlist" lives in
                              the trailing overflow menu. Detail view
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
                              press preview shape (padded, frame
                              (maxWidth: 360)). Pinned via
                              .contentShape(.contextMenuPreview,
                              Rectangle()) so the anticipation phase
                              matches the row's natural square shape.
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
                              "(no X)"). Each row's HStack ends with
                              .contentShape(Rectangle()) so the entire
                              row width is hit-testable when wrapped
                              in a Button (Buttons hit-test their
                              label's natural shape, which excludes
                              Spacer regions). Sharing the row shapes
                              also lets each tab pass the same view
                              as long-press preview: closure for parity.
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
                              Rectangle()) so the anticipation shape
                              matches the row's natural square shape
                              (no separate rounded inset stage). Custom
                              preview: view at frame(maxWidth: 360) for
                              consistent breathing room across rows in
                              portrait and graceful shrink in landscape.
                              Owns the .sheet that hosts EditInfoView.
                              .alignmentGuide(.listRowSeparatorLeading)
                              pins the row separator to the cell's
                              leading edge (matches album-art left).
                              Forwards optional titleOverride +
                              subtitleOverride to TrackRow + the
                              long-press preview's TrackRow (used by
                              SearchView).
        RowTapFeedback.swift  RowTapButtonStyle: ButtonStyle with
                              haptic-only feedback (light impact tick
                              on press-down, no scale / opacity
                              change). The earlier scale + opacity
                              animation manifested as a redundant
                              pre-stage of the contextMenu lift on
                              long-press (a row-level grey flash
                              before iOS's own anticipation), so it
                              was removed; the contextMenu's own
                              visuals are sufficient feedback.
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
