import Foundation
import MediaPlayer
import UIKit

// Bridges AudioPlayer state to MPNowPlayingInfoCenter (lock screen + Control
// Center display, AirPods notifications, future CarPlay) and registers
// MPRemoteCommandCenter handlers (play / pause / next / prev / scrub from
// outside the app).
//
// Re-implemented in Swift rather than reusing the desktop's
// NowPlayingBridge.mm: the surface is small, the desktop file's
// macOS-specific quirks (StatusBarItem, MacWindowHelper) aren't relevant on
// iOS, and the Swift version is half the line count.
@MainActor
final class NowPlayingController
{
    private weak var audio:        AudioPlayer?
    private var      lastTrackPath: String?

    init(audio: AudioPlayer)
    {
        self.audio = audio
        registerRemoteCommands()

        // AudioPlayer notifies us on every play / pause / resume / stop /
        // seek transition. The system extrapolates elapsed time from the
        // last (elapsed, rate) we set, so we don't need to push on every
        // currentTime tick.
        audio.onPlaybackStateChanged = { [weak self] in self?.refresh() }
    }

    func refresh()
    {
        guard let audio = audio else { return }

        guard let track = audio.currentTrack
        else
        {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            lastTrackPath = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle:                    track.displayTitle,
            MPMediaItemPropertyPlaybackDuration:         audio.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audio.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate:        audio.isPlaying ? 1.0 : 0.0,
        ]
        if !track.artist.isEmpty { info[MPMediaItemPropertyArtist]     = track.artist }
        if !track.album.isEmpty  { info[MPMediaItemPropertyAlbumTitle] = track.album  }

        // If the artwork is already in the cache, attach it synchronously so
        // the lock-screen / Control Center never flickers from "no art" to
        // "with art" on a track change.
        if let cached = ArtworkCache.shared.cached(for: track.filePath)
        {
            info[MPMediaItemPropertyArtwork] =
                MPMediaItemArtwork(boundsSize: cached.size) { _ in cached }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // First time we see this track, kick off an async art load if it
        // wasn't in the cache. Subsequent refreshes for the same track skip
        // re-loading.
        let isNewTrack = (track.filePath != lastTrackPath)
        lastTrackPath = track.filePath
        if isNewTrack && info[MPMediaItemPropertyArtwork] == nil
        {
            let path = track.filePath
            Task { [weak self] in
                guard let img = await loadArtwork(for: path) else { return }
                guard let self = self,
                      self.audio?.currentTrack?.filePath == path
                else { return }
                let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                current[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = current
            }
        }
    }

    private func registerRemoteCommands()
    {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget
        { [weak self] _ in
            self?.audio?.resume()
            return .success
        }
        center.pauseCommand.addTarget
        { [weak self] _ in
            self?.audio?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget
        { [weak self] _ in
            self?.audio?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget
        { [weak self] _ in
            self?.audio?.playNext()
            return .success
        }
        center.previousTrackCommand.addTarget
        { [weak self] _ in
            self?.audio?.playPrev()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget
        { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            self?.audio?.seek(to: e.positionTime)
            return .success
        }
    }
}
