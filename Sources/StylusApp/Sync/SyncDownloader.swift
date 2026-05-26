import Foundation

// Orchestrates a single Mac → iPhone sync session: preflight free-
// space check, per-file download into a staging dir, atomic swap of
// the staging tree into the user-picked music + podcast folders,
// playlists.json clobber, libcache invalidation.
//
// All file writes land inside the user-picked roots (musicFolderURL,
// podcastFolderURL) under hidden staging subdirs first, so a
// killed sync leaves only the staging dir dirty -- the user-visible
// library is untouched until the final swap pass at the end of a
// successful session.

@MainActor
final class SyncDownloader: ObservableObject
{
    enum Phase: Equatable
    {
        case idle
        case preflight
        case downloading(currentIndex: Int, total: Int, currentName: String)
        case swapping
        case writingPlaylists
        case done
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .idle

    // Per-file progress: bytes received / bytes total across the
    // entire session. Drives the progress bar in SyncView.
    @Published private(set) var bytesReceived: Int64 = 0
    @Published private(set) var bytesTotal:    Int64 = 0

    private let client:        SyncClient
    private let musicRoot:     URL
    private let podcastRoot:   URL?
    private let playlistStore: PlaylistStore

    // Folder name used inside each root for in-flight files. Hidden
    // dot prefix so the C++ scanner's hidden-file filter ignores it
    // (the project's scanner skips entries beginning with ".").
    private static let stagingDirName = ".stylus-sync-staging"

    init(client:        SyncClient,
         musicRoot:     URL,
         podcastRoot:   URL?,
         playlistStore: PlaylistStore)
    {
        self.client        = client
        self.musicRoot     = musicRoot
        self.podcastRoot   = podcastRoot
        self.playlistStore = playlistStore
    }

    // The full sync flow. Throws on terminal failure; the calling
    // SwiftUI view binds the published phase + bytes to a progress
    // UI and surfaces errors via the .failed phase.
    func run(cancellation: @escaping () -> Bool = { false }) async throws
    {
        do
        {
            phase = .preflight
            let manifest = try await client.fetchManifest()

            // Refuse manifests we don't understand. v1 is the only
            // schema this client implements; a future v2 server
            // could be silently misinterpreted if we just decoded
            // through.
            guard manifest.version == 1 else
            {
                throw Error.versionMismatch(
                    serverVersion: manifest.version)
            }

            try preflight(manifest: manifest)

            // Fetch playlists BEFORE we touch the user-visible
            // library. If /v1/playlists fails (server down,
            // malformed JSON, token revoked), we abort here while
            // music files are still all in their staging dir and
            // the user's iPhone library is untouched. The payload
            // is held in memory until after the music swap; we
            // write playlists.json as the very last step.
            let playlistsPayload = try await client.fetchPlaylists()

            bytesTotal    = manifest.totalBytes
            bytesReceived = 0

            try await stageAll(manifest: manifest, cancellation: cancellation)
            try Task.checkCancellation()

            phase = .swapping
            try swapStaging(manifest: manifest)

            phase = .writingPlaylists
            try writePlaylistsPayload(playlistsPayload)

            invalidateLibraryCache()
            playlistStore.reload()

            phase = .done
        }
        catch
        {
            phase = .failed(message: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Preflight

    private func preflight(manifest: SyncManifest) throws
    {
        // Compare manifest.totalBytes × 1.05 against the music root's
        // available capacity. We use volumeAvailableCapacityFor-
        // ImportantUsage so the OS reports the figure it would let
        // us actually consume.
        let values = try musicRoot.resourceValues(forKeys:
            [.volumeAvailableCapacityForImportantUsageKey]
        )
        let available: Int64 = Int64(
            values.volumeAvailableCapacityForImportantUsage ?? 0
        )
        let need: Int64 = Int64(Double(manifest.totalBytes) * 1.05)
        if available < need
        {
            throw Error.outOfDisk(needed: need, available: available)
        }
    }

    // MARK: - Staging

    private func stageAll(
        manifest:     SyncManifest,
        cancellation: @escaping () -> Bool
    ) async throws
    {
        let total = manifest.music.count + manifest.podcasts.count
        var index = 0

        for entry in manifest.music
        {
            try Task.checkCancellation()
            if cancellation() { throw CancellationError() }
            index += 1
            try await downloadEntry(entry, root: .music,
                                    indexLabel: (index, total))
        }
        for entry in manifest.podcasts
        {
            try Task.checkCancellation()
            if cancellation() { throw CancellationError() }
            index += 1
            try await downloadEntry(entry, root: .podcast,
                                    indexLabel: (index, total))
        }
    }

    private func downloadEntry(
        _ entry:       SyncManifest.Entry,
        root:          SyncClient.FileRoot,
        indexLabel:    (Int, Int)
    ) async throws
    {
        phase = .downloading(currentIndex: indexLabel.0,
                             total:        indexLabel.1,
                             currentName:  entry.rel)

        try await downloadOne(rel: entry.rel,
                              size: entry.size,
                              root: root)
        bytesReceived += entry.size

        if let styl = entry.styl, let stylSize = entry.stylSize
        {
            // The .styl sidecar is at the same relative position as
            // the audio file but with the sidecar's filename swapped
            // in for the last component (the server's manifest gives
            // us the filename, we own the dir path).
            let stylRel = siblingRel(audioRel: entry.rel, sidecarName: styl)
            try await downloadOne(rel: stylRel,
                                  size: stylSize,
                                  root: root)
            bytesReceived += stylSize
        }
        if let art = entry.art, let artSize = entry.artSize
        {
            let artRel = siblingRel(audioRel: entry.rel, sidecarName: art)
            try await downloadOne(rel: artRel,
                                  size: artSize,
                                  root: root)
            bytesReceived += artSize
        }
    }

    private func downloadOne(
        rel:  String,
        size: Int64,
        root: SyncClient.FileRoot
    ) async throws
    {
        // Delta-sync fast path: if the file is ALREADY at its final
        // position with the expected byte count, skip the download
        // entirely. This is what makes a second-and-onward sync
        // fast -- the previous run swapped staging out to final,
        // and unchanged tracks won't match anything in staging, so
        // without this check we'd re-download the whole library
        // every time. swapOne handles a missing staging entry as a
        // no-op so we don't need to touch the swap phase.
        //
        // Size match isn't bulletproof (a re-encode that lands at
        // the same length wouldn't be detected) but the common
        // cases of "added a track" / "edited metadata sidecar" /
        // "no change" are caught correctly.
        let finalURL = finalURLFor(rel: rel, root: root)
        if let existingSize = try? FileManager.default.attributesOfItem(
            atPath: finalURL.path)[.size] as? Int64,
           existingSize == size
        {
            return
        }

        let stagingURL = stagingURLFor(rel: rel, root: root)

        // Retry loop: 3 attempts with 1s / 2s / 4s exponential
        // backoff between them. Each attempt reads the current
        // on-disk staging size first, so a partial file from a
        // dropped previous attempt is resumed via Range rather
        // than re-downloaded from scratch. CancellationError and
        // SyncClient.Error.unauthorized are NOT retried -- the
        // former is user intent, the latter needs a re-pair that
        // only the UI can drive.
        var lastError: Swift.Error?
        for attempt in 0..<3
        {
            if let existingSize = try? FileManager.default.attributesOfItem(
                atPath: stagingURL.path)[.size] as? Int64,
               existingSize == size
            {
                return
            }

            let resumeFrom: Int64 = {
                if let n = try? FileManager.default.attributesOfItem(
                    atPath: stagingURL.path)[.size] as? Int64,
                   n > 0, n < size
                {
                    return n
                }
                return 0
            }()

            do
            {
                try await client.downloadFile(
                    root:            root,
                    rel:             rel,
                    to:              stagingURL,
                    resumeFromBytes: resumeFrom
                )
                return
            }
            catch is CancellationError
            {
                throw CancellationError()
            }
            catch SyncClient.Error.unauthorized
            {
                throw SyncClient.Error.unauthorized
            }
            catch
            {
                lastError = error
                if attempt < 2
                {
                    let delayNs = UInt64(1_000_000_000)
                                * UInt64(1 << attempt)
                    try? await Task.sleep(nanoseconds: delayNs)
                    try Task.checkCancellation()
                }
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    // MARK: - Swap

    private func swapStaging(manifest: SyncManifest) throws
    {
        let fm = FileManager.default
        for entry in manifest.music
        {
            try swapOne(rel: entry.rel, root: .music)
            if let styl = entry.styl
            {
                try swapOne(rel: siblingRel(audioRel: entry.rel,
                                            sidecarName: styl),
                            root: .music)
            }
            if let art = entry.art
            {
                try swapOne(rel: siblingRel(audioRel: entry.rel,
                                            sidecarName: art),
                            root: .music)
            }
        }
        for entry in manifest.podcasts
        {
            try swapOne(rel: entry.rel, root: .podcast)
            if let styl = entry.styl
            {
                try swapOne(rel: siblingRel(audioRel: entry.rel,
                                            sidecarName: styl),
                            root: .podcast)
            }
            if let art = entry.art
            {
                try swapOne(rel: siblingRel(audioRel: entry.rel,
                                            sidecarName: art),
                            root: .podcast)
            }
        }
        // Prune empty staging dirs after a successful swap.
        try? fm.removeItem(at: musicRoot.appendingPathComponent(
            Self.stagingDirName, isDirectory: true))
        if let podRoot = podcastRoot
        {
            try? fm.removeItem(at: podRoot.appendingPathComponent(
                Self.stagingDirName, isDirectory: true))
        }
    }

    private func swapOne(rel: String, root: SyncClient.FileRoot) throws
    {
        let fm     = FileManager.default
        let source = stagingURLFor(rel: rel, root: root)
        let dest   = finalURLFor(rel: rel, root: root)

        // No staging file means downloadOne skipped this entry
        // because the final-position file was already the right
        // size (delta-sync fast path). Nothing to move.
        if !fm.fileExists(atPath: source.path) { return }

        let parent = dest.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        if fm.fileExists(atPath: dest.path)
        {
            // replaceItemAt does the right atomic move when both ends
            // are on the same filesystem.
            _ = try fm.replaceItemAt(dest, withItemAt: source)
        }
        else
        {
            try fm.moveItem(at: source, to: dest)
        }
    }

    // MARK: - Playlists + cache

    private func writePlaylistsPayload(_ payload: SyncPlaylistsPayload) throws
    {
        // Rewrite music-root-relative trackPaths to iOS absolute
        // paths under the user's picked music root.
        let absoluteRoot = musicRoot.path
        let rewritten = payload.playlists.map
        { p -> [String: Any] in
            [
                "id":         p.id,
                "name":       p.name,
                "trackPaths": p.trackPaths.map
                {
                    (absoluteRoot as NSString).appendingPathComponent($0)
                }
            ]
        }

        let dest = try playlistStoreURL()

        let json = try JSONSerialization.data(
            withJSONObject: rewritten,
            options:        [.prettyPrinted, .sortedKeys]
        )
        let tmp = dest.appendingPathExtension("tmp")
        try json.write(to: tmp, options: .atomic)

        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path)
        {
            _ = try fm.replaceItemAt(dest, withItemAt: tmp)
        }
        else
        {
            try fm.moveItem(at: tmp, to: dest)
        }
    }

    private func playlistStoreURL() throws -> URL
    {
        let fm = FileManager.default
        let support = try fm.url(for:               .applicationSupportDirectory,
                                 in:                .userDomainMask,
                                 appropriateFor:    nil,
                                 create:            true)
        let stylusDir = support.appendingPathComponent("Stylus", isDirectory: true)
        try fm.createDirectory(at: stylusDir,
                               withIntermediateDirectories: true)
        return stylusDir.appendingPathComponent("playlists.json")
    }

    // Delete the C++ libcache so the next launch's scanner re-reads
    // every .styl sidecar fresh. The cache lives one level up in the
    // sandbox's Application Support (NOT inside Stylus/).
    private func invalidateLibraryCache()
    {
        let fm = FileManager.default
        guard let support = try? fm.url(for:               .applicationSupportDirectory,
                                        in:                .userDomainMask,
                                        appropriateFor:    nil,
                                        create:            false)
        else { return }
        // The C++ side writes to "Stylus.libcache.json" at the
        // userApplicationDataDirectory root on iOS, which Swift's
        // applicationSupportDirectory maps to.
        let cache = support.appendingPathComponent("Stylus.libcache.json")
        try? fm.removeItem(at: cache)
    }

    // MARK: - Path helpers

    private func stagingURLFor(rel: String,
                               root: SyncClient.FileRoot) -> URL
    {
        let base = root == .music ? musicRoot
                                  : (podcastRoot ?? musicRoot)
        return base
            .appendingPathComponent(Self.stagingDirName, isDirectory: true)
            .appendingPathComponent(rel, isDirectory: false)
    }

    private func finalURLFor(rel: String,
                             root: SyncClient.FileRoot) -> URL
    {
        let base = root == .music ? musicRoot
                                  : (podcastRoot ?? musicRoot)
        return base.appendingPathComponent(rel, isDirectory: false)
    }

    private func siblingRel(audioRel: String, sidecarName: String) -> String
    {
        let nsAudio = audioRel as NSString
        let parent  = nsAudio.deletingLastPathComponent
        return parent.isEmpty
            ? sidecarName
            : (parent as NSString).appendingPathComponent(sidecarName)
    }

    enum Error: Swift.Error
    {
        case outOfDisk(needed: Int64, available: Int64)
        case versionMismatch(serverVersion: Int)
    }
}
