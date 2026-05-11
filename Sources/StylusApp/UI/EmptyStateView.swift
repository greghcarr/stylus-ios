import SwiftUI

// iOS-16-compatible stand-in for SwiftUI 17's ContentUnavailableView.
// Wraps the content in a HStack with Spacers so the message lands at the
// horizontal centre of the screen instead of the centre of any inset
// section that contains it (List overlays especially can pin against the
// section's leading edge instead of the screen's).
//
// .ignoresSafeArea(.container) on the outer frame is what pins this
// to the SCREEN'S vertical centre rather than the inset content
// area's centre. Without it, the frame is squeezed between the nav
// bar above and the TransportBar (added as a safeAreaInset) below;
// their asymmetry shifts the available-area centre slightly below
// the screen's geometric centre, which reads as "the empty-state is
// too low" to the user. Extending into the container safe areas
// gives us the full screen height to centre against; the chrome
// still draws on top so nothing is clipped or hidden.
//
// We DO respect the keyboard safe area (note: .container, not
// .all). When SearchView's empty state renders while the keyboard
// is up, the available area shrinks to "above-the-keyboard" and
// the prompt re-centres into that band -- otherwise it would sit
// at the geometric centre of the screen and disappear behind the
// keyboard.
struct EmptyStateView<Action: View>: View
{
    let title:       String
    let systemImage: String
    let message:     String?
    let action:      Action

    init(title:                  String,
         systemImage:            String,
         message:                String?  = nil,
         @ViewBuilder action:    () -> Action)
    {
        self.title       = title
        self.systemImage = systemImage
        self.message     = message
        self.action      = action()
    }

    var body: some View
    {
        HStack(spacing: 0)
        {
            Spacer(minLength: 0)
            VStack(spacing: 12)
            {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                if let message = message
                {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                action
            }
            .padding()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container)
    }
}

// Convenience overload for callers that don't need a trailing
// action: omit the closure entirely. Same shape as the original
// init so every existing call site keeps working unchanged.
extension EmptyStateView where Action == EmptyView
{
    init(title:                  String,
         systemImage:            String,
         message:                String? = nil)
    {
        self.init(title:       title,
                  systemImage: systemImage,
                  message:     message)
        { EmptyView() }
    }
}
