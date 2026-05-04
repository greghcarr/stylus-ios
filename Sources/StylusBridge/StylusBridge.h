#ifndef STYLUS_BRIDGE_H
#define STYLUS_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Plain-C view of Stylus::TrackInfo. All const char* fields are UTF-8, never
// NULL (empty strings are returned as ""). Pointers are valid only for the
// duration of the callback that delivered them, or until the next Stylus_*
// call on the same thread for synchronous-return APIs. Copy what you keep.
typedef struct StylusTrackC
{
    const char* filePath;
    const char* title;
    const char* artist;
    const char* album;
    const char* genre;
    const char* year;
    int32_t     trackNumber;
    double      durationSeconds;
    double      bpm;
    const char* musicalKey;
    double      lufs;
    int32_t     isPodcast;
    const char* podcast;
    int64_t     dateAddedMillis;
    int32_t     playCount;
} StylusTrackC;

// Initialise JUCE's message thread integration. Must be called once from the
// main thread before any other Stylus_* function. Idempotent.
void Stylus_Initialize(void);

// --- Library scanning ---

typedef struct StylusLibrary StylusLibrary;
typedef StylusLibrary* StylusLibraryHandle;

// Creates a library bound to the given music + podcast folder paths
// (UTF-8 absolute). Either set may be empty. Strings are copied; the caller
// retains ownership. Returns NULL on allocation failure. Files under any
// podcast root are excluded from the music scan, so a podcast folder
// nested inside a music folder doesn't double-up.
StylusLibraryHandle Stylus_LibraryCreate(const char* const* musicFolders,
                                         int32_t            musicFolderCount,
                                         const char* const* podcastFolders,
                                         int32_t            podcastFolderCount);

// Cancels any in-flight scan and frees the handle. Must be called from the
// main thread; blocks for up to ~3s waiting for the scanner thread to exit.
void Stylus_LibraryDestroy(StylusLibraryHandle handle);

typedef void (*Stylus_OnTrackFn)(const StylusTrackC* track, void* userData);
typedef void (*Stylus_OnScanDoneFn)(int32_t totalTracksFound, void* userData);

// Loads cached library entries from disk if a cache file exists for the
// handle's folder set. Fires onTrack synchronously once per cached track on
// the calling thread (expected to be the main thread). Returns the number
// of tracks loaded; 0 indicates a cache miss (no file, mismatched folder
// set, or parse error) and the caller should fall back to a fresh scan.
//
// Intended call pattern:
//     Stylus_LibraryLoadCache(...);   // instant repopulate from disk
//     Stylus_LibraryStartScan(...);   // background fresh scan, atomically
//                                     // replaces the in-memory library
//                                     // when complete and rewrites cache
int32_t Stylus_LibraryLoadCache(StylusLibraryHandle handle,
                                Stylus_OnTrackFn onTrack,
                                void* userData);

// Starts a background scan. onTrack fires once per discovered track on the
// main thread; onDone fires once on the main thread when the scan completes.
// Scanned tracks are also written to the disk cache so the next launch can
// repopulate via Stylus_LibraryLoadCache.
void Stylus_LibraryStartScan(StylusLibraryHandle handle,
                             Stylus_OnTrackFn onTrack,
                             Stylus_OnScanDoneFn onDone,
                             void* userData);

// --- .styl sidecar I/O ---

// Reads the .styl sidecar for the given audio path into outTrack. Only fields
// present in the sidecar are populated; other fields are zero / "". Returns 1
// if the sidecar existed and parsed, 0 otherwise. The const char* pointers in
// *outTrack share thread-local storage and are valid until the next call to
// Stylus_StylLoad on the same thread.
int32_t Stylus_StylLoad(const char* trackPath, StylusTrackC* outTrack);

// Writes the given track to its .styl sidecar. Internally re-loads the
// sidecar first to preserve fields the caller didn't touch (playCount,
// dateAdded, lufs, etc.); the caller only has to populate the fields they
// want to overwrite. Returns 1 on success.
int32_t Stylus_StylSave(const StylusTrackC* track);

// --- Background BPM / key analysis ---

typedef struct StylusAnalysis StylusAnalysis;
typedef StylusAnalysis* StylusAnalysisHandle;

// Fired on the main thread for each analysis lifecycle event.
typedef void (*Stylus_OnAnalysisEventFn)(const StylusTrackC* track, void* userData);

// Creates an analysis engine. The three callbacks fire on the main thread:
//   onQueued   - track was just enqueued (skipped if already analysed).
//   onStarted  - engine started running BPM / key on this track.
//   onAnalysed - finished; the StylusTrackC has fresh bpm + musicalKey
//                (and the .styl sidecar has been written to disk).
StylusAnalysisHandle Stylus_AnalysisCreate(Stylus_OnAnalysisEventFn onQueued,
                                           Stylus_OnAnalysisEventFn onStarted,
                                           Stylus_OnAnalysisEventFn onAnalysed,
                                           void* userData);

// Cancels any in-flight analysis and frees the handle.
void Stylus_AnalysisDestroy(StylusAnalysisHandle handle);

// Enqueues a single track. The engine skips the track outright if both
// `knownBpm` > 0 and `knownKey` is non-empty (a cheap pre-check that
// avoids spinning up the worker thread for already-analysed tracks).
// Caller-owned strings are copied; safe to deallocate after the call.
void Stylus_AnalysisQueue(StylusAnalysisHandle handle,
                          const char* trackPath,
                          double knownBpm,
                          const char* knownKey);

// Cancels every queued track. The currently-running track finishes and
// fires onAnalysed normally.
void Stylus_AnalysisCancel(StylusAnalysisHandle handle);

// --- iTunes Search lookup ---

typedef struct StylusLookup StylusLookup;
typedef StylusLookup* StylusLookupHandle;

typedef void (*Stylus_OnLookupEventFn)(const StylusTrackC* track, void* userData);
typedef void (*Stylus_OnLookupCompletedFn)(const StylusTrackC* track,
                                           const char* status,
                                           int32_t isBatch,
                                           void* userData);
typedef void (*Stylus_OnLookupSuspendedFn)(void* userData);

// Creates a lookup engine that queries the public iTunes Search API for
// each enqueued track. Callbacks fire on the main thread:
//   onQueued    - track was just queued
//   onStarted   - engine started this track
//   onCompleted - finished; status is human-readable ("Found: <album>",
//                 "No match", "Network error"); isBatch flags art-only or
//                 batch-mode jobs vs single-track jobs
//   onSuspended - fires once if the engine self-suspends after consecutive
//                 network failures; no further events arrive after that
StylusLookupHandle Stylus_LookupCreate(Stylus_OnLookupEventFn onQueued,
                                       Stylus_OnLookupEventFn onStarted,
                                       Stylus_OnLookupCompletedFn onCompleted,
                                       Stylus_OnLookupSuspendedFn onSuspended,
                                       void* userData);

void Stylus_LookupDestroy(StylusLookupHandle handle);

// Full lookup: fills missing fields (artist / album / year / genre /
// trackNumber) on the .styl sidecar AND downloads cover art into a
// .styl-art.jpg sidecar. overwrite=1 replaces existing fields rather
// than only filling blanks.
void Stylus_LookupQueue(StylusLookupHandle handle,
                        const char* trackPath,
                        const char* artist,
                        const char* album,
                        const char* title,
                        int32_t overwrite);

// Artwork-only variant: writes the .styl-art.jpg sidecar; .styl metadata
// fields are NOT modified.
void Stylus_LookupQueueArtOnly(StylusLookupHandle handle,
                               const char* trackPath,
                               const char* artist,
                               const char* album);

void Stylus_LookupCancel(StylusLookupHandle handle);

// --- Album artwork ---

// Extracts embedded artwork bytes (JPEG or PNG) from the audio file at the
// given UTF-8 path. Returns a malloc'd buffer the caller must release via
// Stylus_FreeArtworkBytes. Returns NULL and sets *outSize = 0 if the file
// has no embedded artwork or it can't be read.
unsigned char* Stylus_ExtractArtwork(const char* trackPath, size_t* outSize);

// Releases a buffer returned by Stylus_ExtractArtwork. NULL is a no-op.
void Stylus_FreeArtworkBytes(unsigned char* bytes);

#ifdef __cplusplus
}
#endif

#endif
