import SwiftUI
import UIKit

// ButtonStyle that adds visual + haptic feedback to a tappable row:
// briefly scales to 97 % and dims to 65 % opacity while the user's
// finger is on the row, fires a light impact haptic on press-down.
//
// We intentionally do NOT attach a custom DragGesture / simultaneous-
// Gesture for press tracking -- that approach interferes with List
// scrolling (the gesture intercepts touch-down events that should
// belong to List's scroll recognizer, so the user can't drag the
// list anymore). Button's own internal press recognizer feeds
// configuration.isPressed correctly: it activates on touch-down,
// deactivates if the touch slides past the system's scroll
// threshold, and never fights List for control of the scroll
// gesture.
//
// For NavigationLink-based rows we don't apply this style; SwiftUI
// already renders the standard list-row gray-on-press highlight on
// those, which is the iOS-native feedback there.
struct RowTapButtonStyle: ButtonStyle
{
    func makeBody(configuration: Configuration) -> some View
    {
        configuration.label
            // Override Button's default accent-coloured label rendering
            // so the row's text + symbols stay in their natural colours
            // (.primary, .secondary) instead of becoming the system
            // accent (blue by default). This is the same effect as
            // .buttonStyle(.plain) used to provide.
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.65 : 1.0)
            // Asymmetric animation: ease into the pressed state so the
            // tap feedback is visible, but SNAP back to normal on
            // release (no animation). Symmetric animation would leak
            // out the back of a long-press / contextMenu interaction
            // -- isPressed stays true while the contextMenu is shown,
            // so on dismissal the row would visibly scale + un-dim
            // back to normal over 0.12 s. The user described that
            // tail as a "gray background growing larger with straight
            // corners", which is exactly what the back-half of this
            // animation looked like layered under the system menu's
            // own dismissal animation.
            .animation(configuration.isPressed ? .easeOut(duration: 0.12) : nil,
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed)
            { _, isNowPressed in
                if isNowPressed
                {
                    HapticFeedback.tapTick()
                }
            }
    }
}
