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

    func deletePlaylists(at offsets: IndexSet)
    {
        playlists.remove(atOffsets: offsets)
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
