import SwiftUI
import UIKit

// ButtonStyle for tappable rows. Haptic-only feedback: a light
// impact tick fires on press-down, no scale / opacity change.
//
// Earlier versions ramped the row to 97 % scale + 65 % opacity on
// press-down to mimic iOS's tap feedback. That visual leaked into
// the long-press / contextMenu interaction -- the row would dim and
// shrink during the system's hold threshold (the "square-cornered
// grey flash" the user reported as a redundant pre-stage of the
// context menu animation). The contextMenu's own anticipation +
// lift visuals are sufficient feedback for a long-press; for taps,
// the haptic + the navigation/playback action firing immediately
// is enough acknowledgement that the press registered. Removing the
// visual feedback keeps the row visually static until the system
// menu actually opens, eliminating the redundant pre-stage.
//
// We intentionally do NOT attach a custom DragGesture /
// simultaneousGesture for press tracking -- that approach
// interferes with List scrolling (the gesture intercepts
// touch-down events that should belong to List's scroll
// recognizer, so the user can't drag the list anymore). Button's
// own internal press recognizer feeds configuration.isPressed
// correctly without fighting List for the scroll gesture.
struct RowTapButtonStyle: ButtonStyle
{
    func makeBody(configuration: Configuration) -> some View
    {
        configuration.label
            // Override Button's default accent-coloured label rendering
            // so the row's text + symbols stay in their natural colours
            // (.primary, .secondary) instead of becoming the system
            // accent (blue by default). Same effect as
            // .buttonStyle(.plain) used to provide.
            .foregroundStyle(.primary)
            .onChange(of: configuration.isPressed)
            { _, isNowPressed in
                if isNowPressed
                {
                    HapticFeedback.tapTick()
                }
            }
    }
}
