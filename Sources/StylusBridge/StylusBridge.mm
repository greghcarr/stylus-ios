#include "StylusBridge.h"

#include "library/LibraryScanner.h"
#include "library/LibraryCache.h"
#include "audio/StylFile.h"
#include "audio/TrackInfo.h"

#include <juce_events/juce_events.h>
#include <juce_core/juce_core.h>

#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace
{

// Holds UTF-8 byte storage alongside a TrackInfo so the const char* fields
// inside a StylusTrackC stay valid for the lifetime of this owner.
struct TrackBytes
{
    Stylus::TrackInfo info;
    std::string filePath, title, artist, album, genre, year, musicalKey, podcast;

    explicit TrackBytes (Stylus::TrackInfo t)
        : info (std::move (t))
    {
        filePath   = info.file.getFullPathName().toStdString();
        title      = info.title.toStdString();
        artist     = info.artist.toStdString();
        album      = info.album.toStdString();
        genre      = info.genre.toStdString();
        year       = info.year.toStdString();
        musicalKey = info.musicalKey.toStdString();
        podcast    = info.podcast.toStdString();
    }

    StylusTrackC asC() const noexcept
    {
        StylusTrackC c{};
        c.filePath        = filePath.c_str();
        c.title           = title.c_str();
        c.artist          = artist.c_str();
        c.album           = album.c_str();
        c.genre           = genre.c_str();
        c.year            = year.c_str();
        c.trackNumber     = info.trackNumber;
        c.durationSeconds = info.durationSecs;
        c.bpm             = info.bpm;
        c.musicalKey      = musicalKey.c_str();
        c.lufs            = static_cast<double> (info.lufs);
        c.isPodcast       = info.isPodcast ? 1 : 0;
        c.podcast         = podcast.c_str();
        c.dateAddedMillis = info.dateAdded;
        c.playCount       = info.playCount;
        return c;
    }
};

} // namespace

// Definition of the opaque struct forward-declared in StylusBridge.h. Lives at
// namespace scope so the tag name matches across the C / C++ boundary.
struct StylusLibrary
{
    std::vector<juce::File>        folders;
    Stylus::LibraryScanner         scanner;
    std::vector<Stylus::TrackInfo> scanBuffer;   // accumulates tracks during
                                                 // the current scan so we can
                                                 // write the cache on done
};

namespace
{

bool foldersMatch (const std::vector<juce::File>& a,
                   const std::vector<juce::File>& b)
{
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i)
        if (a[i].getFullPathName() != b[i].getFullPathName())
            return false;
    return true;
}

} // namespace

extern "C" {

void Stylus_Initialize (void)
{
    static std::once_flag flag;
    std::call_once (flag, []() { juce::initialiseJuce_GUI(); });
}

StylusLibraryHandle Stylus_LibraryCreate (const char* const* musicFolders,
                                          int32_t folderCount)
{
    auto* h = new (std::nothrow) StylusLibrary();
    if (h == nullptr) return nullptr;

    if (musicFolders != nullptr && folderCount > 0)
    {
        h->folders.reserve (static_cast<size_t> (folderCount));
        for (int32_t i = 0; i < folderCount; ++i)
        {
            if (musicFolders[i] == nullptr) continue;
            h->folders.emplace_back (juce::String (juce::CharPointer_UTF8 (musicFolders[i])));
        }
    }
    return h;
}

void Stylus_LibraryDestroy (StylusLibraryHandle handle)
{
    auto* h = handle;
    if (h == nullptr) return;
    h->scanner.cancelScan();
    delete h;
}

int32_t Stylus_LibraryLoadCache (StylusLibraryHandle handle,
                                 Stylus_OnTrackFn onTrack,
                                 void* userData)
{
    auto* h = handle;
    if (h == nullptr || onTrack == nullptr) return 0;

    std::vector<Stylus::TrackInfo> tracks;
    std::vector<juce::File>        cachedMusicFolders;
    std::vector<juce::File>        cachedPodcastFolders;
    if (! Stylus::LibraryCache::tryLoad (tracks, cachedMusicFolders, cachedPodcastFolders))
        return 0;

    if (! foldersMatch (cachedMusicFolders, h->folders))
        return 0;

    int32_t count = 0;
    for (auto& t : tracks)
    {
        TrackBytes tb (std::move (t));
        const StylusTrackC c = tb.asC();
        onTrack (&c, userData);
        ++count;
    }
    return count;
}

void Stylus_LibraryStartScan (StylusLibraryHandle handle,
                              Stylus_OnTrackFn onTrack,
                              Stylus_OnScanDoneFn onDone,
                              void* userData)
{
    auto* h = handle;
    if (h == nullptr) return;

    h->scanBuffer.clear();

    h->scanner.onBatchReady = [h, onTrack, userData] (std::vector<Stylus::TrackInfo> batch)
    {
        for (auto& t : batch)
        {
            // Keep a copy in the bridge buffer for the cache write at scan
            // end, AND fire the per-track callback for the caller's UI.
            h->scanBuffer.push_back (t);
            if (onTrack != nullptr)
            {
                TrackBytes tb (std::move (t));
                const StylusTrackC c = tb.asC();
                onTrack (&c, userData);
            }
        }
    };

    h->scanner.onScanComplete = [h, onDone, userData] (int total)
    {
        Stylus::LibraryCache::save (h->scanBuffer, h->folders, /*podcastFolders*/ {});
        h->scanBuffer.clear();
        if (onDone != nullptr) onDone (total, userData);
    };

    h->scanner.scanFolders (h->folders, /*podcastFolders*/ {});
}

int32_t Stylus_StylLoad (const char* trackPath, StylusTrackC* outTrack)
{
    if (trackPath == nullptr || outTrack == nullptr) return 0;

    static thread_local std::unique_ptr<TrackBytes> storage;

    Stylus::TrackInfo info;
    info.file = juce::File (juce::String (juce::CharPointer_UTF8 (trackPath)));
    const bool existed = Stylus::StylFile::load (info);

    storage = std::make_unique<TrackBytes> (std::move (info));
    *outTrack = storage->asC();
    return existed ? 1 : 0;
}

// Forward-declared so we don't have to depend on AlbumArtExtractor's internal
// header (it doesn't ship one - the function is a pure-ObjC++ extern "C" in
// AlbumArtExtractor.mm so the .cpp wrapper can stay JUCE-only on the desktop).
unsigned char* Stylus_extractEmbeddedArtwork (const char* utf8Path, size_t* outSize);

unsigned char* Stylus_ExtractArtwork (const char* trackPath, size_t* outSize)
{
    if (outSize != nullptr) *outSize = 0;
    if (trackPath == nullptr || outSize == nullptr) return nullptr;
    return Stylus_extractEmbeddedArtwork (trackPath, outSize);
}

void Stylus_FreeArtworkBytes (unsigned char* bytes)
{
    std::free (bytes);
}

} // extern "C"
