import Foundation
import Combine

// Persistent store for the user's playlists. Mirrors the desktop's
// PlaylistStore (External/stylus/src/library/PlaylistStore.cpp)
// shape so the eventual sync engine can move JSON between the two
// without translation.
//
// Storage: Library/Application Support/Stylus/playlists.json. App
// Support survives reinstalls only when the user restores from a
// backup, but it doesn't get cleared by iOS at low-storage time
// (Caches does). Documents would also work but is exposed via
// UIFileSharingEnabled when that's on, and these aren't the kind
// of files we want users editing manually.
@MainActor
final class PlaylistStore: ObservableObject
{
    @Published private(set) var playlists: [Playlist] = []

    private let storeURL: URL
    private var nextId:   Int = 1

    init()
    {
        let fm = FileManager.default
        let support = (try? fm.url(for:               .applicationSupportDirectory,
                                   in:                .userDomainMask,
                                   appropriateFor:    nil,
                                   create:            true))
                    ?? fm.temporaryDirectory
        let stylusDir = support.appendingPathComponent("Stylus", isDirectory: true)
        try? fm.createDirectory(at: stylusDir, withIntermediateDirectories: true)
        storeURL = stylusDir.appendingPathComponent("playlists.json")
        load()
    }

    // MARK: - Mutations

    @discardableResult
    func createPlaylist(name: String) -> Playlist
    {
        let p = Playlist(id: nextId, name: name, trackPaths: [])
        nextId += 1
        playlists.append(p)
        save()
        return p
    }

    func renamePlaylist(id: Int, to newName: String)
    {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = newName
        save()
    }

    func deletePlaylist(id: Int)
    {
        playlists.removeAll { $0.id == id }
        save()
    }

    func movePlaylists(from source: IndexSet, to destination: Int)
    {
        playlists.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func contains(trackPath: String, in playlistId: Int) -> Bool
    {
        playlists.first(where: { $0.id == playlistId })?
                 .trackPaths.contains(trackPath) ?? false
    }

    func addTracks(_ paths: [String], to playlistId: Int)
    {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].trackPaths.append(contentsOf: paths)
        save()
    }

    func removeTrackPaths(at offsets: IndexSet, from playlistId: Int)
    {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].trackPaths.remove(atOffsets: offsets)
        save()
    }

    func moveTrackPaths(from source: IndexSet, to destination: Int, in playlistId: Int)
    {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].trackPaths.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Path migration

    // Walks every playlist's stored trackPaths and rewrites any entry
    // that no longer matches a current library track exactly but does
    // match one by sandbox-relative tail (i.e. the iOS app data-
    // container UUID changed since the path was originally stored).
    // The result is the playlists.json file is rewritten with current-
    // container paths, so subsequent in-process lookups hit the fast
    // direct-match path and the JSON stays in sync with the live
    // library.
    //
    // Called once per launch from RootView/StylusApp after the
    // library has loaded its cache. No-op when nothing needs
    // migrating, so this is cheap to call unconditionally.
    func migratePathsIfNeeded(against libraryTracks: [Track])
    {
        guard !playlists.isEmpty, !libraryTracks.isEmpty else { return }

        // Build the same lookup tables PlaylistDetailView uses --
        // direct-path and sandbox-relative-tail -- so we can match
        // a stale path by tail and recover the canonical filePath.
        var byPath: [String: String] = [:]
        var byTail: [String: String] = [:]
        for t in libraryTracks
        {
            byPath[t.filePath] = t.filePath
            let tail = Self.sandboxRelativeTail(t.filePath)
            if tail != t.filePath
            {
                byTail[tail] = t.filePath
            }
        }

        var changed = 0
        for pi in playlists.indices
        {
            for ti in playlists[pi].trackPaths.indices
            {
                let stored = playlists[pi].trackPaths[ti]
                if byPath[stored] != nil { continue }   // already current
                let tail = Self.sandboxRelativeTail(stored)
                if let canonical = byTail[tail], canonical != stored
                {
                    playlists[pi].trackPaths[ti] = canonical
                    changed += 1
                }
            }
        }

        if changed > 0 { save() }
    }

    // Same path-tail logic PlaylistDetailView uses; duplicated here
    // so PlaylistStore doesn't need to import the UI module / view
    // file. The two implementations must stay in sync -- if you
    // change one, change the other (or extract to a shared helper).
    private static func sandboxRelativeTail(_ path: String) -> String
    {
        guard let containers = path.range(of: "/Containers/Data/Application/")
        else { return path }
        let after = path[containers.upperBound...]
        guard let firstSlash = after.firstIndex(of: "/")
        else { return path }
        return String(after[after.index(after: firstSlash)...])
    }

    // MARK: - Persistence

    private func save()
    {
        do
        {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(playlists)
            try data.write(to: storeURL, options: .atomic)
        }
        catch
        {
            print("PlaylistStore: save failed: \(error)")
        }
    }

    // Public re-read entry point. The sync flow writes a new
    // playlists.json directly via FileManager, then calls this so
    // the in-memory list refreshes for any SwiftUI view bound to
    // @Published playlists.
    func reload()
    {
        load()
    }

    private func load()
    {
        guard let data = try? Data(contentsOf: storeURL) else
        {
            // First launch (or wiped): start empty. nextId stays 1.
            return
        }
        do
        {
            playlists = try JSONDecoder().decode([Playlist].self, from: data)
            // Recompute nextId from the highest existing id so future
            // creates don't collide with anything already in the file.
            // We don't store nextId separately on disk -- the desktop
            // does, but we can derive it here without losing anything,
            // and sync logic later can reconcile across both sides.
            nextId = (playlists.map(\.id).max() ?? 0) + 1
        }
        catch
        {
            print("PlaylistStore: load failed (\(error)); starting empty")
            playlists = []
            nextId    = 1
        }
    }
}
