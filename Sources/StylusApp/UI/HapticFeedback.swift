import UIKit

// Shared haptic feedback generator. A single long-lived instance is
// cheaper than allocating a fresh UIImpactFeedbackGenerator on every
// tap, and the system keeps the haptic engine warm between events
// fired in quick succession so consecutive taps fire without the
// ~150 ms first-call latency.
//
// We deliberately do NOT call .prepare() at app launch: the haptic
// engine auto-deactivates after ~3 s of inactivity, which logs
// "AVHapticClient finish: Player was not running" / "core haptics
// engine finished with error" to the console. That deactivation is
// benign but the spam is noisy. Letting impactOccurred() warm the
// engine on its own (with a small first-call latency that's barely
// perceptible) keeps the console clean.
enum HapticFeedback
{
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)

    // Light "tick" used for row-tap feedback.
    static func tapTick()
    {
        lightImpact.impactOccurred()
    }
}
