import Foundation

// Holds the user-picked music folder, persists access across launches via a
// security-scoped bookmark in UserDefaults, and keeps the security scope
// active for the lifetime of the store so the C++ scanner and AVAudioPlayer
// can read files from the folder by plain POSIX path.
final class MusicFolderStore: ObservableObject
{
    @Published private(set) var folderURL: URL?

    private var didStartScope = false

    private static let bookmarkKey = "MusicFolderBookmark"

    init()
    {
        loadBookmark()
    }

    deinit
    {
        stopScope()
    }

    func set(url: URL)
    {
        stopScope()

        didStartScope = url.startAccessingSecurityScopedResource()

        do
        {
            let bookmark = try url.bookmarkData()
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        }
        catch
        {
            print("MusicFolderStore: failed to write bookmark: \(error)")
        }

        folderURL = url
    }

    func clear()
    {
        stopScope()
        folderURL = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    private func loadBookmark()
    {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }

        var isStale = false
        do
        {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            didStartScope = url.startAccessingSecurityScopedResource()
            guard didStartScope
            else
            {
                UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
                return
            }

            folderURL = url

            if isStale, let fresh = try? url.bookmarkData()
            {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            }
        }
        catch
        {
            print("MusicFolderStore: failed to resolve bookmark: \(error)")
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        }
    }

    private func stopScope()
    {
        if let url = folderURL, didStartScope
        {
            url.stopAccessingSecurityScopedResource()
        }
        didStartScope = false
    }
}
