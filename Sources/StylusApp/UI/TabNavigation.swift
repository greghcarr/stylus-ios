import SwiftUI

// One enum case per top-level tab. Used both as the TabView's
// selection identity (.tag(...) on each NavigationStack) and as the
// menu item list driving the tab-title menu, so adding a tab is one
// place: just add a case.
enum AppTab: String, CaseIterable, Identifiable
{
    case library, artists, albums, podcasts, search

    var id: String { rawValue }

    var title: String
    {
        switch self
        {
        case .library:  return "All Songs"
        case .artists:  return "Artists"
        case .albums:   return "Albums"
        case .podcasts: return "Podcasts"
        case .search:   return "Search"
        }
    }

    var systemImage: String
    {
        switch self
        {
        case .library:  return "music.note.list"
        case .artists:  return "music.mic"
        case .albums:   return "square.stack"
        case .podcasts: return "mic"
        case .search:   return "magnifyingglass"
        }
    }
}

// Holds the currently-selected tab. Injected via a custom
// EnvironmentKey (NOT @EnvironmentObject) so consumers don't
// subscribe to its @Published current. Subscribing would re-render
// every consumer on every tab switch -- which, for the tab title
// menu's view tree, manifested as visible flicker (the menu being
// rebuilt mid-dismiss) and a stream of UIKit log spam:
//   "Called updateVisibleMenuWithBlock: while no context menu is
//    visible. This won't do anything."
//
// RootView still holds the router as a @StateObject so the TabView
// can bind its selection to $router.current; consumers that only
// need to WRITE to current (like the title-menu buttons) read the
// router from the custom environment value below and mutate it
// directly.
final class TabRouter: ObservableObject
{
    @Published var current: AppTab = .library
}

private struct TabRouterKey: EnvironmentKey
{
    static let defaultValue: TabRouter? = nil
}

extension EnvironmentValues
{
    var tabRouter: TabRouter?
    {
        get { self[TabRouterKey.self] }
        set { self[TabRouterKey.self] = newValue }
    }
}

// Applied to each tab's root view (after .navigationTitle). We
// build the menu manually via .toolbar { ToolbarItem(placement:
// .principal) { Menu { ... } label: { ... } } } so the chevron and
// the menu trigger are guaranteed to render -- the iOS-16
// .toolbarTitleMenu modifier silently no-ops in some
// configurations (notably when the principal toolbar slot is
// already claimed or when @EnvironmentObject wiring inside the
// modifier doesn't propagate to the system-hosted title view).
//
// Using a Menu with a custom label (HStack of Text + chevron.down)
// gives us a tappable, visibly-affordant title in both the large
// and inline title display modes. The buttons inside the menu show
// the current tab via a checkmark next to its label.
struct TabTitleMenu: ViewModifier
{
    let title: String

    @EnvironmentObject              var folder:    MusicFolderStore
    @Environment(\.tabRouter) private var tabRouter: TabRouter?

    func body(content: Content) -> some View
    {
        content
            .navigationBarTitleDisplayMode(.inline)
            // Force the nav-bar backdrop visible so it stays put
            // during tab switches. Default behavior only shows it
            // when content is scrolled under the bar; during the
            // cross-fade between two NavigationStacks neither tab
            // owns the backdrop, so it briefly vanishes -- which
            // reads as a flicker at the top of the screen.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar
            {
                ToolbarItem(placement: .principal)
                {
                    // SwiftUI's Menu inside .toolbar gets torn down
                    // and rebuilt on every parent re-render (which
                    // happens constantly during the library scan as
                    // LibraryStore.tracks updates). Even with
                    // EquatableView wrapping it, the menu visibly
                    // flickered when open. Using a UIKit UIButton
                    // with a UIMenu set ONCE at creation, plus a
                    // UIDeferredMenuElement that fetches items
                    // lazily at menu-open time, sidesteps the whole
                    // SwiftUI rebuild path.
                    TabTitleButton(
                        title:         title,
                        availableTabs: availableTabs,
                        onSelect:
                        { tab in
                            // Defer so the menu finishes dismissing
                            // before we flip tabs (avoids the
                            // updateVisibleMenuWithBlock log spam).
                            DispatchQueue.main.async
                            {
                                tabRouter?.current = tab
                            }
                        }
                    )
                }
            }
    }

    // Hide the Podcasts entry when no podcast folder is configured,
    // matching the TabView's conditional rendering.
    private var availableTabs: [AppTab]
    {
        AppTab.allCases.filter
        { tab in
            tab != .podcasts || folder.podcastFolderURL != nil
        }
    }
}

// UIKit-backed nav-bar title button with a UIMenu. The button's
// menu is set ONCE in makeUIView using a UIDeferredMenuElement that
// pulls items from the Coordinator's stored state at menu-open
// time -- so SwiftUI's frequent updateUIView calls (one per parent
// re-render) only update the Coordinator's stored values, never
// reassign button.menu, and the underlying UIContextMenuInteraction
// instance survives unchanged.
private struct TabTitleButton: UIViewRepresentable
{
    let title:         String
    let availableTabs: [AppTab]
    let onSelect:      (AppTab) -> Void

    func makeCoordinator() -> Coordinator
    {
        Coordinator()
    }

    final class Coordinator
    {
        // Mutable state read by the deferred menu element each time
        // the menu opens. updateUIView writes to these; the
        // UIDeferredMenuElement closure captures `self` weakly and
        // reads them.
        var availableTabs: [AppTab]          = []
        var onSelect:      (AppTab) -> Void  = { _ in }
    }

    func makeUIView(context: Context) -> UIButton
    {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true

        // UIDeferredMenuElement.uncached: items are recomputed every
        // time the menu opens, but the menu structure itself is
        // never reassigned. This is the key to keeping the menu
        // stable across SwiftUI re-renders.
        let coord    = context.coordinator
        let deferred = UIDeferredMenuElement.uncached
        { [weak coord] completion in
            guard let coord = coord else { completion([]); return }
            let actions = coord.availableTabs.map
            { tab in
                UIAction(
                    title: tab.title,
                    image: UIImage(systemName: tab.systemImage)
                )
                { _ in
                    coord.onSelect(tab)
                }
            }
            completion(actions)
        }
        button.menu = UIMenu(title: "", children: [deferred])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context)
    {
        // Push current SwiftUI props into the Coordinator so the
        // deferred element will see them on the next open.
        context.coordinator.availableTabs = availableTabs
        context.coordinator.onSelect      = onSelect

        // Title + chevron, rebuilt cheaply. Title font matches the
        // SwiftUI .title2.weight(.bold) we used previously (22 pt).
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            NSAttributedString(
                string: title,
                attributes:
                [
                    .font:            UIFont.systemFont(ofSize: 22,
                                                       weight: .bold),
                    .foregroundColor: UIColor.label
                ]
            )
        )
        config.image            = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: .semibold
            )
        )?.withTintColor(.secondaryLabel,
                         renderingMode: .alwaysOriginal)
        config.imagePlacement   = .trailing
        config.imagePadding     = 6
        config.contentInsets    = .zero
        button.configuration    = config
    }
}

extension View
{
    func tabTitleMenu(_ title: String) -> some View
    {
        modifier(TabTitleMenu(title: title))
    }
}
