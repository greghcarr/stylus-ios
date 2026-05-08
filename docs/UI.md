# UI

NowPlayingSheet's sheetY model, custom navigation chrome, TabRouter env-key
decision, splash / launch storyboard alignment, and the "presentation only
on user gesture" rule.

## NowPlayingSheet sheetY model
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

## Sheet presentation is gesture-only
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

## Custom navigation: hidden tab bar + title-menu chevron
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

## TabRouter: custom env key, not @EnvironmentObject
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

## Row taps: Buttons + RowTapButtonStyle, not NavigationLink
Every list row across the app (track rows, group rows for artists /
albums / genres / playlists / podcasts / search hits, plus the My
Library entry rows in HomeView) is a `Button` with
`buttonStyle(RowTapButtonStyle())` that programmatically appends to
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

## Splash + launch storyboard
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

## Adding a new SwiftUI view checklist
1. New file under `Sources/StylusApp/UI/`. Use `@EnvironmentObject` for the
   stores rather than direct refs.
2. No `make regen` needed; XcodeGen's `path: Sources/StylusApp` glob picks
   up new files on next regen, but Xcode's own file watcher catches them
   without regenerating in most cases.
3. Every list-row view (Button or any other top-level ForEach child) gets
   `.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }` so the divider
   extends symmetrically. Apply on every row even if the row currently
   has no leading icon, so future leading icons don't accidentally shift
   the divider.
4. Row layouts that include a `Spacer` end with `.contentShape(Rectangle())`
   so the entire row width is hit-testable when wrapped in a Button.
5. For navigation: prefer `Button { router?.path.append(value) } label:
   { Row(...) }` with `.buttonStyle(RowTapButtonStyle())` over
   `NavigationLink(value:)` -- keeps row press visuals consistent and
   avoids the iOS 18 NavigationLink + simultaneousGesture interaction.
