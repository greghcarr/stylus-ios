import SwiftUI

// One enum case per top-level tab. HomeView is the entry point; the
// other cases are reached via tap on a HomeView row, and the user
// returns via the .topBarLeading "Home" button on every non-Home tab.
enum AppTab: String, CaseIterable, Identifiable
{
    case home, library, artists, albums, genres, podcasts, search

    var id: String { rawValue }

    var title: String
    {
        switch self
        {
        case .home:     return "My Library"
        case .library:  return "All Songs"
        case .artists:  return "Artists"
        case .albums:   return "Albums"
        case .genres:   return "Genres"
        case .podcasts: return "Podcasts"
        case .search:   return "Search"
        }
    }

    var systemImage: String
    {
        switch self
        {
        case .home:     return "house.fill"
        case .library:  return "music.note.list"
        case .artists:  return "music.mic"
        case .albums:   return "square.stack"
        case .genres:   return "tag.fill"
        case .podcasts: return "mic"
        case .search:   return "magnifyingglass"
        }
    }
}

// Holds the currently-selected tab. Injected via a custom
// EnvironmentKey (NOT @EnvironmentObject) so consumers don't
// subscribe to its @Published current. Subscribing would re-render
// every consumer on every tab switch.
//
// RootView holds the router as a @StateObject and switches the
// rendered NavigationStack on router.current; HomeView's row taps
// and the leading "Home" button on other tabs read the router from
// the custom environment value below and mutate `current` directly.
final class TabRouter: ObservableObject
{
    @Published var current: AppTab = .home

    // Drives the root NavigationStack's push history. Mutated from
    // HomeView (Button taps append an AppTab here, which the
    // NavigationStack resolves via .navigationDestination(for:)) and
    // from anywhere else that needs to programmatically pop / push.
    //
    // HomeView uses a Button rather than a NavigationLink because
    // SwiftUI's NavigationLink in a List interacts poorly with the
    // simultaneousGesture in .rowTapFeedback() on iOS 18: the drag
    // gesture's .onEnded fires as a "drag complete" event that
    // pre-empts NavigationLink's tap recognizer, swallowing the
    // navigation. Buttons handle simultaneous gestures cleanly, so
    // we route Home -> tab pushes through this path manually and
    // reserve NavigationLinks for the other tabs (which don't share
    // the iOS-18 bug because they push via a non-Home stack frame).
    @Published var path:    NavigationPath = NavigationPath()
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

// Applied to each tab's root view (Home / All Songs / Artists /
// Albums / Podcasts / Search). Sets the inline navigation title and
// pins the nav-bar backdrop visible (so it doesn't flash during tab
// switches). On every non-Home tab, also adds a leading "<- Home"
// button mirroring the iOS standard back-button styling.
//
// Earlier this modifier hosted a UIKit-backed UIButton + UIMenu in
// the principal toolbar slot for tab-to-tab switching. HomeView now
// owns that selection role, so the chevron + tappable-title were
// removed; only the title text + the back-to-Home button remain.
struct TabTitleMenu: ViewModifier
{
    let title: String

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View
    {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // Hide the system back button on every non-Home tab so
            // our custom chevron-only button (added below) is the
            // only one visible. The system back would auto-generate
            // a "<- My Library" label since RootView's
            // NavigationStack pushed the destination from HomeView.
            .navigationBarBackButtonHidden(title != AppTab.home.title)
            // Force the nav-bar backdrop visible so it stays put
            // during tab switches. Default behaviour only shows it
            // when content is scrolled under the bar; during the
            // cross-fade between two NavigationStacks neither tab
            // owns the backdrop, so it briefly vanishes -- which
            // reads as a flicker at the top of the screen.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar
            {
                // Leading "back to Home" button on every non-Home
                // tab. RootView's tabsLayer is a switch on
                // router.current (not a NavigationStack push), so
                // iOS doesn't auto-generate a back chevron; we add
                // one explicitly that flips tabRouter.current =
                // .home, mirroring the system's chevron + previous-
                // title style.
                if title != AppTab.home.title
                {
                    ToolbarItem(placement: .topBarLeading)
                    {
                        Button
                        {
                            dismiss()
                        }
                        label:
                        {
                            // Chevron only, no text. Accessibility
                            // label keeps the button discoverable
                            // for VoiceOver since there's no
                            // visible label.
                            //
                            // The frame + contentShape pair expands
                            // the hit target beyond the chevron's
                            // tight glyph bounds (~14pt wide) to a
                            // 44 x 44 pt area, matching Apple's HIG
                            // minimum tappable size. Without it,
                            // taps that land near the chevron but
                            // not directly on the glyph were
                            // silently missing. Default-aligned
                            // (.center) so the chevron sits in the
                            // middle of its hit area rather than
                            // hugging the leading edge.
                            Image(systemName: "chevron.backward")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                                .accessibilityLabel(AppTab.home.title)
                        }
                    }
                }

                // Custom principal toolbar item replaces the system-
                // rendered .navigationTitle text, letting us pick a
                // font size larger than .inlineLarge while keeping
                // the title centred in the nav bar. .navigationTitle
                // is still set above so SwiftUI / accessibility still
                // know the screen's title for context.
                ToolbarItem(placement: .principal)
                {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
    }
}

extension View
{
    func tabTitleMenu(_ title: String) -> some View
    {
        modifier(TabTitleMenu(title: title))
    }
}
