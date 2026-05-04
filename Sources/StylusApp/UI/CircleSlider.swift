import SwiftUI

// Drop-in replacement for the bits of SwiftUI.Slider we use, with a plain
// circular thumb instead of the iOS 26 pill thumb. Capsule track, filled
// portion in tint colour, white circle thumb with a soft shadow.
struct CircleSlider: View
{
    @Binding var value: Double
    let range:                ClosedRange<Double>
    let onEditingChanged:     (Bool) -> Void

    @State private var isDragging = false

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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged
                    { drag in
                        if !isDragging
                        {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let centred  = drag.location.x - thumbDiameter / 2
                        let clamped  = max(0, min(usableWidth, centred))
                        let pct      = usableWidth > 0 ? clamped / usableWidth : 0
                        value = range.lowerBound + Double(pct) * span
                    }
                    .onEnded
                    { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: thumbDiameter)
    }
}
