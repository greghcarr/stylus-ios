import SwiftUI

// iOS-16-compatible stand-in for SwiftUI 17's ContentUnavailableView.
// Wraps the content in a HStack with Spacers so the message lands at the
// horizontal centre of the screen instead of the centre of any inset
// section that contains it (List overlays especially can pin against the
// section's leading edge instead of the screen's).
struct EmptyStateView: View
{
    let title:       String
    let systemImage: String
    let message:     String?

    init(title: String, systemImage: String, message: String? = nil)
    {
        self.title       = title
        self.systemImage = systemImage
        self.message     = message
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
            }
            .padding()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
