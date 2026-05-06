import SwiftUI

// Trailing footer row for any List of songs. Two jobs:
//
//   1. While a track is playing, reserve `height` pt at the bottom
//      so the last few rows don't scroll under the persistent
//      TransportBar. RootView pins the bar via .safeAreaInset on
//      each NavigationStack, which is supposed to extend the
//      contained List's bottom inset automatically. On iOS 26 that
//      propagation is unreliable for List specifically, so we keep
//      this hand-rolled spacer cross-version.
//
//   2. Always (whether or not a track is playing) suppress the
//      last actual song row's bottom divider. Plain List draws a
//      separator at every row boundary including the LAST row's
//      bottom edge. The user described that as "the last song has
//      a divider under it that disappears when I tap that song" --
//      the disappearance was this spacer flipping into existence
//      and absorbing / hiding the boundary via
//      .listRowSeparator(.hidden). To make that suppression
//      unconditional we render the spacer always, just with zero
//      height + zero insets when no track is playing so it takes
//      no visible space.
struct TransportBarBottomSpacer: View
{
    @EnvironmentObject var audio: AudioPlayer

    static let height: CGFloat = 80

    var body: some View
    {
        Color.clear
            .frame(height: audio.currentTrack != nil ? Self.height : 0)
            // Strip the cell's default vertical padding so the
            // collapsed-state row genuinely takes no space, not
            // ~20 pt of dead air per List.
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
