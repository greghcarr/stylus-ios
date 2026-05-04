import SwiftUI

// Drop-in replacement for the bits of SwiftUI.Slider we use, with a plain
// circular thumb instead of the iOS 26 pill thumb. Capsule track, filled
// portion in tint colour, white circle thumb with a soft shadow.
struct CircleSlider: View
{
    @Binding var value: Double
    let range:                ClosedRange<Double>
    let onEditingChanged:     (Bool) -> Void

    @State private var isDragging   = false
    // Captured at gesture-start so each drag tick can apply a
    // delta from THAT starting value rather than the live value
    // (the live value is the one we're mutating, which would
    // produce compounding drift).
    @State private var initialValue: Double = 0

    private let trackHeightIdle:    CGFloat = 4
    private let trackHeightActive:  CGFloat = 7
    private let thumbDiameter:      CGFloat = 22
    private let thumbScaleActive:   CGFloat = 1.18

    private var animation: Animation
    {
        .spring(response: 0.32, dampingFraction: 0.72)
    }

    var body: some View
    {
        GeometryReader
        { geo in
            let width        = geo.size.width
            let usableWidth  = max(0, width - thumbDiameter)
            let span         = max(range.upperBound - range.lowerBound, 0.0001)
            let progress     = max(0, min(1, (value - range.lowerBound) / span))
            let thumbLeading = progress * usableWidth
            let trackHeight  = isDragging ? trackHeightActive : trackHeightIdle

            ZStack(alignment: .leading)
            {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: trackHeight)
                    .animation(animation, value: isDragging)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: thumbLeading + thumbDiameter / 2,
                           height: trackHeight)
                    .animation(animation, value: isDragging)

                Circle()
                    .fill(Color.white)
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                    )
                    .overlay
                    {
                        Circle()
                            .fill(Color(uiColor: .systemGray3))
                            .frame(width: thumbDiameter * 0.42,
                                   height: thumbDiameter * 0.42)
                            .scaleEffect(isDragging ? 1.0 : 0.0)
                            .opacity(isDragging ? 1.0 : 0.0)
                            .animation(animation, value: isDragging)
                    }
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .scaleEffect(isDragging ? thumbScaleActive : 1.0)
                    .shadow(color: .black.opacity(isDragging ? 0.28 : 0.18),
                            radius: isDragging ? 4 : 2,
                            y:      isDragging ? 2 : 1)
                    .offset(x: thumbLeading)
                    .animation(animation, value: isDragging)
                    // Gesture is on the THUMB only, not the whole
                    // track. Tapping somewhere else on the track
                    // does nothing -- the user must grab the thumb
                    // and drag it. Translation is added to the
                    // captured-at-start initialValue so we don't
                    // get compounding drift from reading the live
                    // (mutating) value.
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged
                            { drag in
                                if !isDragging
                                {
                                    isDragging   = true
                                    initialValue = value
                                    onEditingChanged(true)
                                }
                                let deltaPct =
                                    drag.translation.width
                                    / max(usableWidth, 1)
                                let newValue =
                                    initialValue
                                    + Double(deltaPct) * span
                                value = max(range.lowerBound,
                                            min(range.upperBound,
                                                newValue))
                            }
                            .onEnded
                            { _ in
                                isDragging = false
                                onEditingChanged(false)
                            }
                    )
            }
            .frame(maxWidth: .infinity,
                   maxHeight: .infinity,
                   alignment: .leading)
        }
        .frame(height: thumbDiameter)
    }
}
