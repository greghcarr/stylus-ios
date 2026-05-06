import SwiftUI
import UniformTypeIdentifiers

// Per-tab scope for the trailing overflow menu's contents. Different
// tabs care about different subsets of the library-management
// actions; this lets each tab dial in only the items the user
// actually expects to find there.
enum LibraryActionsScope
{
    // My Library (HomeView): full set -- change music folder,
    // change/choose/remove podcasts folder, re-scan folders.
    case home

    // All Songs (LibraryListView): just music-related items --
    // change music folder, re-scan folders.
    case music

    // Podcasts: just podcast-related items -- change podcasts
    // folder, re-scan folders. The Podcasts tab is only visible
    // when a podcast folder is already set, so we don't need a
    // "choose" affordance here.
    case podcasts
}

// Reusable trailing-toolbar modifier that hosts the scope-aware
// overflow menu plus the scan-progress spinner that replaces the
// menu while the background scan is running. Tabs that should not
// expose any of these actions (Artists / Albums / Genres /
// Playlists / Search) simply don't apply this modifier.
struct LibraryActionsToolbar: ViewModifier
{
    let scope: LibraryActionsScope

    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var folder:  MusicFolderStore

    @State private var showMusicPicker:   Bool = false
    @State private var showPodcastPicker: Bool = false

    func body(content: Content) -> some View
    {
        content
            .toolbar { menuToolbar }
            .fileImporter(
                isPresented:         $showMusicPicker,
                allowedContentTypes: [.folder]
            )
            { result in
                if case .success(let url) = result
                {
                    folder.setMusic(url: url)
                    rescan()
                }
            }
            .fileImporter(
                isPresented:         $showPodcastPicker,
                allowedContentTypes: [.folder]
            )
            { result in
                if case .success(let url) = result
                {
                    folder.setPodcast(url: url)
                    rescan()
                }
            }
    }

    // Used after picking a new folder via fileImporter -- we want
    // the cache-then-scan flow with the skip-scan optimization
    // intact (the cache load will return zero tracks for a freshly-
    // changed folder, so the skip check fails and a full scan runs
    // anyway).
    private func rescan()
    {
        library.scan(music:   folder.musicFolderURL,
                     podcast: folder.podcastFolderURL)
    }

    // Used when the user explicitly hits the Rescan menu item or
    // removes a podcasts folder. forceFullScan: true bypasses the
    // skip-scan optimization so externally-edited metadata gets
    // picked up.
    private func fullRescan()
    {
        library.scan(music:         folder.musicFolderURL,
                     podcast:       folder.podcastFolderURL,
                     forceFullScan: true)
    }

    @ToolbarContentBuilder
    private var menuToolbar: some ToolbarContent
    {
        ToolbarItem(placement: .topBarTrailing)
        {
            if library.isScanning
            {
                ProgressView()
            }
            else if folder.musicFolderURL != nil
            {
                // UIKit-backed button so the menu's UIContextMenu-
                // Interaction is set ONCE in makeUIView and survives
                // the parent's frequent re-renders during analyse /
                // lookup (which would otherwise rebuild a SwiftUI
                // Menu's UIKit host and produce visible flicker +
                // the "updateVisibleMenuWithBlock while no context
                // menu is visible" log spam). Same pattern as the
                // tab title menu in TabNavigation.swift.
                LibraryActionsButton(
                    scope:                 scope,
                    podcastsFolderSet:     folder.podcastFolderURL != nil,
                    // Re-scan is always a force-full-scan: the user
                    // is explicitly asking us to re-read every
                    // file's metadata in case tags changed externally.
                    onRescan:              { fullRescan() },
                    onChangeMusicFolder:   { showMusicPicker = true },
                    onChangePodcastFolder: { showPodcastPicker = true },
                    onRemovePodcastFolder: { folder.clearPodcast()
                                             fullRescan() },
                    onChoosePodcastFolder: { showPodcastPicker = true }
                )
            }
        }
    }
}

extension View
{
    func libraryActionsToolbar(scope: LibraryActionsScope) -> some View
    {
        modifier(LibraryActionsToolbar(scope: scope))
    }
}

// UIKit-backed button hosting the overflow menu. Its UIMenu is set
// once in makeUIView using a UIDeferredMenuElement that pulls the
// item list from the Coordinator's stored state at menu-open time
// -- so SwiftUI's frequent updateUIView calls (one per parent
// re-render) only refresh the Coordinator's mirrored state and
// never reassign button.menu. Result: the UIContextMenuInteraction
// instance is preserved unchanged across re-renders, eliminating
// the same flicker the title menu used to have.
private struct LibraryActionsButton: UIViewRepresentable
{
    let scope:                 LibraryActionsScope
    let podcastsFolderSet:     Bool

    let onRescan:              () -> Void
    let onChangeMusicFolder:   () -> Void
    let onChangePodcastFolder: () -> Void
    let onRemovePodcastFolder: () -> Void
    let onChoosePodcastFolder: () -> Void

    func makeCoordinator() -> Coordinator
    {
        Coordinator()
    }

    final class Coordinator
    {
        var scope:                 LibraryActionsScope = .home
        var podcastsFolderSet:     Bool                = false

        var onRescan:              () -> Void          = {}
        var onChangeMusicFolder:   () -> Void          = {}
        var onChangePodcastFolder: () -> Void          = {}
        var onRemovePodcastFolder: () -> Void          = {}
        var onChoosePodcastFolder: () -> Void          = {}

        // Builds the menu structure from the Coordinator's current
        // state. Called by the UIDeferredMenuElement each time the
        // user opens the menu, so the conditional folder-removal
        // entry reflects the latest podcast-folder presence.
        func buildMenu() -> [UIMenuElement]
        {
            var items: [UIMenuElement] = []

            let changeMusic = UIAction(
                title: "Change music folder\u{2026}",
                image: UIImage(systemName: "music.note")
            )
            { [weak self] _ in self?.onChangeMusicFolder() }

            let changePodcasts = UIAction(
                title: "Change podcasts folder\u{2026}",
                image: UIImage(systemName: "mic")
            )
            { [weak self] _ in self?.onChangePodcastFolder() }

            let choosePodcasts = UIAction(
                title: "Choose podcasts folder\u{2026}",
                image: UIImage(systemName: "mic.badge.plus")
            )
            { [weak self] _ in self?.onChoosePodcastFolder() }

            let removePodcasts = UIAction(
                title:      "Remove podcasts folder",
                image:      UIImage(systemName: "minus.circle"),
                attributes: .destructive
            )
            { [weak self] _ in self?.onRemovePodcastFolder() }

            // Re-scan sits at the bottom of the menu in every
            // scope so the folder-management entries (which the
            // user reaches for less often) don't push it out of
            // sight.
            let rescan = UIAction(
                title: "Re-scan folders",
                image: UIImage(systemName: "arrow.triangle.2.circlepath")
            )
            { [weak self] _ in self?.onRescan() }

            switch scope
            {
            case .home:
                items.append(changeMusic)
                if podcastsFolderSet
                {
                    items.append(changePodcasts)
                    items.append(removePodcasts)
                }
                else
                {
                    items.append(choosePodcasts)
                }
                items.append(rescan)

            case .music:
                items.append(changeMusic)
                items.append(rescan)

            case .podcasts:
                items.append(changePodcasts)
                items.append(rescan)
            }

            return items
        }
    }

    func makeUIView(context: Context) -> UIButton
    {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true

        let deferred = UIDeferredMenuElement.uncached
        { [weak coord = context.coordinator] completion in
            guard let coord = coord else { completion([]); return }
            completion(coord.buildMenu())
        }
        button.menu = UIMenu(title: "", children: [deferred])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context)
    {
        let coord = context.coordinator
        coord.scope                 = scope
        coord.podcastsFolderSet     = podcastsFolderSet
        coord.onRescan              = onRescan
        coord.onChangeMusicFolder   = onChangeMusicFolder
        coord.onChangePodcastFolder = onChangePodcastFolder
        coord.onRemovePodcastFolder = onRemovePodcastFolder
        coord.onChoosePodcastFolder = onChoosePodcastFolder

        // Static ellipsis.circle. Sized via the body text style so
        // it matches sibling SwiftUI ProgressView() sizing in the
        // same toolbar slot when the bar shows the scanning spinner.
        var config           = UIButton.Configuration.plain()
        let symbolConfig     = UIImage.SymbolConfiguration(
                                   textStyle: .body)
        config.image         = UIImage(
            systemName:        "ellipsis.circle",
            withConfiguration: symbolConfig
        )
        button.configuration = config
    }

    // Without this, SwiftUI passes the proposed size (the toolbar's
    // entire available width) down to the UIButton, which then
    // renders huge -- the menu's hit area covered ~2/3 of the
    // screen. Returning the button's intrinsic size constrains the
    // representable to just the image's natural footprint, matching
    // a normal SwiftUI Button in the same slot.
    func sizeThatFits(_ proposal:  ProposedViewSize,
                      uiView:      UIButton,
                      context:     Context) -> CGSize?
    {
        return uiView.intrinsicContentSize
    }
}
