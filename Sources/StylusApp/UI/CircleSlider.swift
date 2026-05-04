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

    private let trackHeight:   CGFloat = 4
    private let thumbDiameter: CGFloat = 22

    var body: some View
    {
        GeometryReader
        { geo in
            let width        = geo.size.width
            let usableWidth  = max(0, width - thumbDiameter)
            let span         = max(range.upperBound - range.lowerBound, 0.0001)
            let progress     = max(0, min(1, (value - range.lowerBound) / span))
            let thumbLeading = progress * usableWidth

            ZStack(alignment: .leading)
            {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: thumbLeading + thumbDiameter / 2,
                           height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                    )
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: thumbLeading)
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
