# Audio

Playback engine, system audio session lifecycle, lock-screen integration,
and the album-art lookup chain.

## Audio engine choice
Picked `AVAudioEngine` + `AVAudioPlayerNode` over `AVAudioPlayer` because
the eventual roadmap (DJ mode: gapless, level meters, EQ / pitch-shift,
two-deck mixing) all needs the engine graph. `AVAudioPlayer` doesn't scale
into any of that; the upgrade later would be a rewrite. `AVAudioEngine`
costs ~30 extra lines in [AudioPlayer.swift](../Sources/StylusApp/Audio/AudioPlayer.swift)
and we get the foundation for free.

Per-track playback flow:
1. `play(_ track)` opens `AVAudioFile`, captures `processingFormat`,
   `length`, and `sampleRate`.
2. `engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)`
   reconnects with each track's native format so the mixer downmixes /
   resamples to the output device. (Files with different formats can
   follow each other without engine.stop() because we re-connect.)
3. `node.scheduleSegment(..., completionCallbackType: .dataPlayedBack)`
   schedules the entire file from `seekFrame` and registers a completion
   handler that bounces onto MainActor and calls `playNext()`.
4. `engine.start()` if needed, `node.play()`.

`currentTime` is computed on a 0.25 s `Timer` from
`node.playerTime(forNodeTime:lastRenderTime)` plus the current
`seekFrame` offset. Seeks `node.stop()` + `scheduleSegment` from the new
frame so `lastRenderTime` resets and the offset arithmetic stays right.
Pause keeps the buffer scheduled, so `node.play()` resumes seamlessly
without rescheduling.

`pause()` and `resume()` each call `tickCurrentTime()` at the
transition boundary so `currentTime` reflects the renderer's actual
sample position before the change fires `onPlaybackStateChanged`.
Without this, the timer's last (up to 0.25 s stale) sample is what
NowPlayingController publishes to `MPNowPlayingInfoCenter`, and the
lock-screen seek bar drifts behind real playback by up to a tick
on every pause -- compounding into visible misalignment between the
in-app and lock-screen scrubbers.

## AVAudioSession lifecycle
AudioPlayer registers three notification observers on construction:

- **`interruptionNotification`**: fires on phone calls, alarms, and
  another app activating an exclusive audio session (e.g. Apple
  Music starting). On `.began` we call `pause()` so isPlaying flips
  to false and the lock screen / Control Center stay aligned with
  the silent reality. On `.ended` we resume **only** if the
  notification's options include `.shouldResume` -- some
  interruptions hint that the user wants playback back (phone call
  hung up), others don't (Siri "what's the weather"), and forcing
  a resume against the user's intent is worse than leaving the
  track paused.
- **`routeChangeNotification`**: AirPods unplugged, Bluetooth
  speaker walked out of range, headphone cable yanked. We pause on
  `.oldDeviceUnavailable` only; other reasons (new device added,
  category change) don't need our intervention. Mirrors Apple
  Music's "don't suddenly blast out the phone speaker" behaviour.
- **`mediaServicesWereResetNotification`**: the iOS audio server
  restarted under us (rare but documented). Engine + node refs are
  now stale; we `stop()` and re-`configureSession()` so the next
  `play()` rebuilds cleanly. A surviving track + queue position is
  the user's job to resume.

The session category is `.playback` with mode `.default`: standard
"music app" priority, no speech ducking, no measurement-mode
artefacts. The category isn't reconfigured on the fly.

## Now Playing center + remote commands
[NowPlayingController.swift](../Sources/StylusApp/Audio/NowPlayingController.swift)
is constructed once in [StylusApp.swift](../Sources/StylusApp/StylusApp.swift)
with a reference to the `AudioPlayer`. It hooks
`AudioPlayer.onPlaybackStateChanged` (a single closure, not Combine, so
there's only one source of truth for "something playback-relevant
happened") and on every fire writes a fresh
`MPNowPlayingInfoCenter.default().nowPlayingInfo` dictionary with title /
artist / album / duration / elapsed / rate. Once track-changes happen,
it kicks an async `loadArtwork(for:)` off the cache and merges
`MPMediaItemArtwork` into the info dict. If the artwork is already in
the cache (typical when the user just looked at the row), it's attached
synchronously to avoid the lock-screen "no art then art" flicker.

We don't push on every `currentTime` tick: the system extrapolates
elapsed from the last (elapsed, rate) pair we set, so play / pause /
seek transitions are sufficient.

The same controller registers `MPRemoteCommandCenter` handlers
(play / pause / togglePlayPause / next / prev / changePlaybackPosition)
that route into `AudioPlayer`, so lock-screen, Control Center, AirPods,
and (eventually, Phase X) CarPlay all drive the same audio engine.

## Album art loading
[Sources/StylusApp/Library/ArtworkCache.swift](../Sources/StylusApp/Library/ArtworkCache.swift)
exposes two NSCaches keyed by track file path: `thumbnails` (132 px max,
limit 300) for list rows / transport bar / Up Next, and `largeArt`
(1200 px max, limit 8) for the Now Playing hero artwork and
`MPMediaItemArtwork` on the lock screen. The free async helpers
`loadThumbnail(for:)` and `loadFullArtwork(for:)` route to the right
tier; both decode off the main thread on cache miss.

ImageIO downsampling at decode time (via
`CGImageSourceCreateThumbnailAtIndex` with
`kCGImageSourceThumbnailMaxPixelSize`) keeps 1000 x 1000 album art
JPEGs from being decoded into ~4 MB UIImages just to render at 44 pt
thumbnails; thumb decode lands at ~50 KB. The previous full-resolution
cache was the dominant memory pressure source and the proximate cause
of OOM kills when scrolling Up Next on a long queue.

The lookup chain mirrors the desktop's
[AlbumArtExtractor.cpp](../External/stylus/src/audio/AlbumArtExtractor.cpp),
re-implemented in Swift because the desktop's `juce::Image`-returning
function lives in juce_graphics which isn't linked on iOS:

1. **Embedded artwork**: bridge functions
   `Stylus_ExtractArtwork` / `Stylus_FreeArtworkBytes` return malloc'd
   JPEG / PNG bytes via the desktop's
   [AlbumArtExtractor.mm](../External/stylus/src/audio/AlbumArtExtractor.mm)
   (AVFoundation `commonMetadata` query).
2. **Per-track sidecar**: `.<filename>.styl-art.jpg` next to the audio
   file (written by the desktop's Apple Music lookup task).
3. **Folder-level art**: `cover / folder / artwork / album / front`
   with extensions `jpg / jpeg / png` in the audio file's parent
   directory. APFS is case-insensitive so we don't enumerate case
   variants.

Each `TrackRow` runs its own
`.task(id: filePath) { artwork = await loadArtwork(for: filePath) }`,
which is fine because SwiftUI's `List` virtualises and only visible rows
fire their task. Cache hits short-circuit the detached work entirely so
scrolling back is instant.

`Stylus_ExtractArtwork` is a thin wrapper around the existing desktop
`Stylus_extractEmbeddedArtwork`. We forward-declare that function in
[StylusBridge.mm](../Sources/StylusBridge/StylusBridge.mm) rather than
include a header, because the desktop intentionally leaves
`AlbumArtExtractor.mm` JUCE-free so the .mm and the JUCE-flavoured .cpp
wrapper can coexist without translation-unit conflicts (the JUCE Carbon
`Point` / `Component` types collide with AVFoundation's).
