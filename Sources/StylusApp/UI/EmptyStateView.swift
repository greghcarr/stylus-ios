import SwiftUI

// iOS-16-compatible stand-in for SwiftUI 17's ContentUnavailableView.
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
