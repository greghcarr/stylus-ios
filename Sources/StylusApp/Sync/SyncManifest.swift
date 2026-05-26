import Foundation

// Wire-format models for the v1 Mac -> iPhone sync protocol. The
// desktop's SyncManifestBuilder produces these structures as JSON
// over HTTP; SyncClient decodes them with JSONDecoder. Keep this
// file in lock-step with External/stylus/src/sync/SyncManifest{Builder}.h
// -- any field change ships in BOTH sides of the same release.

// Top-level response from GET /v1/manifest. Lists every audio file
// the Mac will hand over, along with the sizes of the file itself
// and its (optional) .styl / .styl-art.jpg sidecars. iOS uses this
// to drive a preflight free-space check, an item-by-item download
// loop, and the cancel-or-resume progress UI.
struct SyncManifest: Codable, Sendable
{
    let version:    Int
    let peer:       Peer
    let music:      [Entry]
    let podcasts:   [Entry]
    let totalBytes: Int64

    struct Peer: Codable, Sendable
    {
        let hostname:   String
        let appVersion: String
    }

    // One audio file. rel is POSIX, root-relative, no leading slash
    // and no ".." (the server's serialiser enforces this; the client
    // re-validates before joining onto its own root). The two
    // sidecar fields are present iff the Mac actually has each
    // sidecar -- absent fields encode "no sidecar to ship".
    struct Entry: Codable, Sendable
    {
        let rel:      String
        let size:     Int64
        let styl:     String?
        let stylSize: Int64?
        let art:      String?
        let artSize:  Int64?
    }
}

// Response from POST /v1/pair. Body is {"pin": "123456"}; success
// returns a bearer token good for the rest of the Mac process's
// lifetime, and the client stamps every subsequent request with
// `Authorization: Bearer <token>`. Failure responses use HTTP 401
// + a Codable error envelope (PairError) so the iOS UI can show
// "wrong PIN" vs. "locked out" without parsing prose.
struct SyncPairResponse: Codable, Sendable
{
    let token: String
}

struct SyncPairError: Codable, Sendable
{
    let code:    String   // "wrongPin" | "lockedOut"
    let message: String
}

// Response from GET /v1/playlists. Mirrors the iOS PlaylistStore's
// on-disk shape (an array of {id, name, trackPaths}), except the
// server emits trackPaths AS MUSIC-ROOT-RELATIVE POSIX strings;
// the client prepends its own iOS music-root absolute path before
// saving to playlists.json. Podcasts aren't in playlists by
// convention on the desktop, so no podcast-root rewrite is needed.
struct SyncPlaylistsPayload: Codable, Sendable
{
    let version:   Int
    let playlists: [Playlist]

    struct Playlist: Codable, Sendable
    {
        let id:         Int
        let name:       String
        let trackPaths: [String]   // music-root-relative POSIX
    }
}
