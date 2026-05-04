import SwiftUI

// Initial app surface: the app icon centred on the system background
// for `displayDuration` seconds, then a soft fade to RootView.
//
// The very first frame of the app is the iOS launch storyboard, but
// Xcode's default for a launch screen is solid black; this view
// covers the brief gap between launch-screen dismissal and our
// first SwiftUI render with the same icon the user just tapped on
// the home screen, so the transition feels continuous.
struct SplashView: View
{
    @State private var hasFinished: Bool = false

    // Shown for this many seconds before fading to the RootView.
    private static let displayDuration: TimeInterval = 1.6
    private static let fadeDuration:    Double       = 0.45

    var body: some View
    {
        ZStack
        {
            if hasFinished
            {
                // RootView's environment objects come from StylusApp's
                // body. By the time this branch is taken, those are
                // already injected and ready.
                RootView()
                    .transition(.opacity)
            }
            else
            {
                splashLayer
                    .transition(.opacity)
            }
        }
        .task
        {
            try? await Task.sleep(
                nanoseconds: UInt64(Self.displayDuration
                                    * 1_000_000_000))
            withAnimation(.easeInOut(duration: Self.fadeDuration))
            {
                hasFinished = true
            }
        }
    }

    private var splashLayer: some View
    {
        ZStack
        {
            Color(uiColor: .systemBackground)

            Image("SplashIcon")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                // Same 180 x 180 + 36 pt corner radius as the
                // launch storyboard's UIImageView, so the moment
                // SwiftUI takes over from the launch chrome the
                // visual is identical -- no pop, no resize. No
                // shadow on either side because the storyboard's
                // clipped UIImageView can't render an outside-
                // bounds shadow without an extra wrapper view.
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 36,
                                            style:        .continuous))
        }
        // .ignoresSafeArea on the ZStack itself (not just the
        // background Color) so the ZStack's frame matches the
        // storyboard's UIWindow-sized root view. Without this the
        // ZStack respects safe areas and centers within the
        // smaller "safe" rect, which on a Dynamic Island device
        // shifts the icon downward by ~30 pt the moment SwiftUI
        // takes over from the storyboard -- the small downward
        // hop the user reported.
        .ignoresSafeArea()
    }
}
