import SwiftUI

// Top-level entry point. A list of tappable rows for All Songs /
// Artists / Albums / Genres / Podcasts / Search; tapping a row
// appends that AppTab to the parent NavigationStack's path (via
// the shared TabRouter), giving us iOS's standard slide-in-from-
// the-right push. The user returns to Home via the leading
// chevron on every non-Home tab (TabTitleMenu calls
// @Environment(\.dismiss)).
//
// The rows are Buttons (not NavigationLinks) because
// .rowTapFeedback()'s simultaneousGesture interacts badly with
// NavigationLink in a List on iOS 18 -- the drag gesture's
// .onEnded fires as a "drag complete" event that pre-empts
// NavigationLink's tap recognizer, so the visual feedback fired
// but the navigation never happened. Buttons handle simultaneous
// gestures cleanly. The other tab roots (Artists / Albums / etc.)
// keep NavigationLink for now since their pushes go through a
// non-Home stack frame and don't reproduce the bug.
struct HomeView: View
{
    @EnvironmentObject              var folder: MusicFolderStore
    @Environment(\.tabRouter)       private var router

    var body: some View
    {
        List
        {
            ForEach(Array(destinations.enumerated()), id: \.element)
            { (index, tab) in
                Button
                {
                    router?.path.append(tab)
                }
                label:
                {
                    HomeRow(tab: tab)
                }
                // RowTapButtonStyle drives the scale + dim + haptic
                // press feedback off Button's own isPressed signal,
                // which correctly defers to List's scroll recognizer
                // when the user's finger slides instead of taps.
                .buttonStyle(RowTapButtonStyle())
                // Pin the row separator's leading edge to the
                // cell's leading edge, matching the other tabs'
                // list rows.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .hideFirstRowSeparator(index == 0)
            }
            TransportBarBottomSpacer()
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .tabTitleMenu(AppTab.home.title)
        .libraryActionsToolbar()
    }

    // All non-Home tabs the user can reach from Home. Podcasts is
    // omitted when no podcast folder is configured (matches the
    // tab-title menu's filter and the TabView's conditional
    // PodcastsView).
    private var destinations: [AppTab]
    {
        AppTab.allCases.filter
        { tab in
            tab != .home
            && (tab != .podcasts || folder.podcastFolderURL != nil)
        }
    }
}

// Single row in the Home list: leading icon (tinted), title text,
// and a trailing chevron indicating "tap to navigate". Because the
// row is a Button (not a NavigationLink), SwiftUI doesn't auto-add
// a list-row chevron, so we draw one explicitly here -- matching
// the system disclosure look of the other tabs' NavigationLink
// rows visually.
private struct HomeRow: View
{
    let tab: AppTab

    var body: some View
    {
        HStack(spacing: 16)
        {
            Image(systemName: tab.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36)

            Text(tab.title)
                .font(.title3)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
