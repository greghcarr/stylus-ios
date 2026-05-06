import Foundation

// Plain value type that round-trips one-for-one with the desktop's
// `Stylus::Playlist` JSON schema (see
// External/stylus/src/library/PlaylistStore.cpp). Same field names,
// same types, same key ("tracks") for the ordered file paths -- so
// the future desktop <-> iOS sync engine just moves bytes and
// re-bases the music-folder prefix on each path between the two
// roots; no schema translation needed.
struct Playlist: Identifiable, Hashable, Codable
{
    var id:         Int
    var name:       String
    var trackPaths: [String]

    private enum CodingKeys: String, CodingKey
    {
        case id
        case name
        case trackPaths = "tracks"
    }
}
