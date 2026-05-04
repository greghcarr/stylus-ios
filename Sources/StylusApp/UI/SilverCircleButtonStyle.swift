import SwiftUI

// Silver circular button style matching the app icon's metallic
// silver tone (top-light to bottom-darker gradient with a subtle
// rim) and the desktop's TransportBar disc buttons (juce::Colour
// 0xffc4c4c4 fill, black or accent icon). Used by every transport
// button in the iOS app: shuffle / prev / play-pause / next /
// repeat in the mini-player and the prev / play-pause / next row
// in the expanded NowPlayingSheet.
//
// The style sets foregroundStyle(.black) on the button label, so
// SF Symbols inside render as black glyphs against the silver fill
// without each call site having to repeat that.
struct SilverCircleButtonStyle: ButtonStyle
{
    // Caller sets the diameter; the icon size stays the caller's
    // responsibility (via .font on the Image).
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View
    {
        configuration.label
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background
            {
                Circle()
                    .fill(silverGradient)
                    .overlay
                    {
                        // Thin darker rim ties the button to the
                        // app icon's edge contour and keeps the
                        // button visible against the bar's frosted
                        // material in light mode.
                        Circle().stroke(Color(white: 0.55),
                                        lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.18),
                            radius: 1.5,
                            y: 1)
            }
            // Press feedback: shrink slightly and darken the
            // gradient. Mirrors the desktop's pressed-state
            // 0xff989898 fill.
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.08),
                       value: configuration.isPressed)
    }

    private var silverGradient: LinearGradient
    {
        LinearGradient(
            colors:
            [
                // Top: closer to the icon's brighter highlight band.
                Color(white: 0.92),
                // Middle: matches the desktop disc rest fill (~c4c4c4).
                Color(white: 0.78),
                // Bottom: slightly darker so the button reads as 3D.
                Color(white: 0.70)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
