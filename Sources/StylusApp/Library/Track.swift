import Foundation

struct Track: Identifiable, Hashable
{
    let filePath:        String
    let title:           String
    let artist:          String
    let album:           String
    let genre:           String
    let year:            String
    let trackNumber:     Int
    let bpm:             Double
    let key:             String
    let durationSeconds: Double
    // Podcast fields. isPodcast is true when the scanner picked the file
    // up under a podcast root; podcast holds the show name (album-tag
    // fallback to the parent folder name).
    let isPodcast:       Bool
    let podcast:         String

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
        self.genre           = String(cString: track.genre)
        self.year            = String(cString: track.year)
        self.trackNumber     = Int(track.trackNumber)
        self.bpm             = track.bpm
        self.key             = String(cString: track.musicalKey)
        self.durationSeconds = track.durationSeconds
        self.isPodcast       = track.isPodcast != 0
        self.podcast         = String(cString: track.podcast)
    }

    var displayTitle: String
    {
        title.isEmpty
            ? URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
            : title
    }

    var subtitle: String
    {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " - ")
    }

    var formattedDuration: String
    {
        guard durationSeconds > 0 else { return "--:--" }
        let total = Int(durationSeconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var formattedBpm: String
    {
        guard bpm > 0 else { return "" }
        return String(format: "%.0f", bpm.rounded())
    }
}
