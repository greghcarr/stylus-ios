import Foundation

// Holds the user-picked music + podcast folders and persists access across
// launches via security-scoped bookmarks in UserDefaults. The scopes stay
// active for the lifetime of the store so the C++ scanner and AVAudioPlayer
// can read by POSIX path without per-call scoping.
final class MusicFolderStore: ObservableObject
{
    @Published private(set) var musicFolderURL:   URL?
    @Published private(set) var podcastFolderURL: URL?

    private var didStartMusicScope:   Bool = false
    private var didStartPodcastScope: Bool = false

    private static let musicBookmarkKey   = "MusicFolderBookmark"
    private static let podcastBookmarkKey = "PodcastFolderBookmark"

    init()
    {
        loadBookmark(key: Self.musicBookmarkKey)
        { [weak self] url, started in
            self?.musicFolderURL     = url
            self?.didStartMusicScope = started
        }
        loadBookmark(key: Self.podcastBookmarkKey)
        { [weak self] url, started in
            self?.podcastFolderURL     = url
            self?.didStartPodcastScope = started
        }
    }

    deinit
    {
        stopScope(url: musicFolderURL,   started: didStartMusicScope)
        stopScope(url: podcastFolderURL, started: didStartPodcastScope)
    }

    // MARK: - Music

    func setMusic(url: URL)
    {
        stopScope(url: musicFolderURL, started: didStartMusicScope)
        didStartMusicScope = url.startAccessingSecurityScopedResource()
        writeBookmark(url: url, key: Self.musicBookmarkKey)
        musicFolderURL = url
    }

    func clearMusic()
    {
        stopScope(url: musicFolderURL, started: didStartMusicScope)
        musicFolderURL     = nil
        didStartMusicScope = false
        UserDefaults.standard.removeObject(forKey: Self.musicBookmarkKey)
    }

    // MARK: - Podcasts

    func setPodcast(url: URL)
    {
        stopScope(url: podcastFolderURL, started: didStartPodcastScope)
        didStartPodcastScope = url.startAccessingSecurityScopedResource()
        writeBookmark(url: url, key: Self.podcastBookmarkKey)
        podcastFolderURL = url
    }

    func clearPodcast()
    {
        stopScope(url: podcastFolderURL, started: didStartPodcastScope)
        podcastFolderURL     = nil
        didStartPodcastScope = false
        UserDefaults.standard.removeObject(forKey: Self.podcastBookmarkKey)
    }

    // MARK: - Internal

    private func writeBookmark(url: URL, key: String)
    {
        do
        {
            let data = try url.bookmarkData()
            UserDefaults.standard.set(data, forKey: key)
        }
        catch
        {
            print("MusicFolderStore: failed to write bookmark for \(key): \(error)")
        }
    }

    private func loadBookmark(key: String,
                              assign: (URL?, Bool) -> Void)
    {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }

        var isStale = false
        do
        {
            let url = try URL(
                resolvingBookmarkData: data,
                options:               [],
                relativeTo:            nil,
                bookmarkDataIsStale:   &isStale
            )

            let started = url.startAccessingSecurityScopedResource()
            guard started
            else
            {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }

            assign(url, true)

            if isStale, let fresh = try? url.bookmarkData()
            {
                UserDefaults.standard.set(fresh, forKey: key)
            }
        }
        catch
        {
            print("MusicFolderStore: failed to resolve bookmark for \(key): \(error)")
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func stopScope(url: URL?, started: Bool)
    {
        if let url = url, started
        {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
