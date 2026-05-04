import SwiftUI

// Transparent footer row that reserves space at the bottom of any List so
// the last items aren't hidden under the persistent TransportBar.
//
// Why this exists: RootView pins the bar via .safeAreaInset(.bottom) on each
// NavigationStack, which is supposed to extend the contained List's bottom
// inset automatically. On iOS 26 that propagation is unreliable for List
// specifically, so the last few rows scroll under the bar instead of
// stopping above it. A transparent listRowBackground row at the end of
// every List works around it cross-version. Conditional on a current track,
// so an empty-queue session doesn't waste 80 pt of dead space.
struct TransportBarBottomSpacer: View
{
    @EnvironmentObject var audio: AudioPlayer

    static let height: CGFloat = 80

    var body: some View
    {
        if audio.currentTrack != nil
        {
            Color.clear
                .frame(height: Self.height)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
}
