import Foundation

struct Track: Identifiable, Hashable
{
    let filePath: String
    let title: String
    let artist: String
    let album: String
    let durationSeconds: Double

    var id: String { filePath }
}

extension Track
{
    init(c track: StylusTrackC)
    {
        self.filePath        = String(cString: track.filePath)
        self.title           = String(cString: track.title)
        self.artist          = String(cString: track.artist)
        self.album           = String(cString: track.album)
        self.durationSeconds = track.durationSeconds
    }

    var displayTitle: String
    {
        title.isEmpty
            ? URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
            : title
    }

    var subtitle: String
    {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    var formattedDuration: String
    {
        guard durationSeconds > 0 else { return "--:--" }
        let total = Int(durationSeconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
