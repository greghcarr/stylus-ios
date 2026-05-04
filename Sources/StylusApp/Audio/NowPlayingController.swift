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
    private weak var audio:          AudioPlayer?
    private var      lastTrackPath:  String?
    // Strong reference to the current track's artwork so we don't lose it
    // when refresh() rebuilds the info dict (e.g. on pause from the lock
    // screen). NSCache can evict under memory pressure; this property keeps
    // a survivor copy for the duration the track is current.
    private var      currentArtwork: UIImage?

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
            lastTrackPath  = nil
            currentArtwork = nil
            return
        }

        // Track changed: reset cached artwork. If it's already in the
        // ArtworkCache, capture it synchronously; otherwise kick an async
        // load that will call refresh() again once it lands.
        if track.filePath != lastTrackPath
        {
            lastTrackPath  = track.filePath
            currentArtwork = ArtworkCache.shared.cachedFullArtwork(for: track.filePath)

            if currentArtwork == nil
            {
                let path = track.filePath
                Task { [weak self] in
                    let img = await loadFullArtwork(for: path)
                    guard let self = self,
                          self.audio?.currentTrack?.filePath == path
                    else { return }
                    self.currentArtwork = img
                    self.refresh()
                }
            }
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle:                    track.displayTitle,
            MPMediaItemPropertyPlaybackDuration:         audio.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audio.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate:        audio.isPlaying ? 1.0 : 0.0,
        ]
        if !track.artist.isEmpty { info[MPMediaItemPropertyArtist]     = track.artist }
        if !track.album.isEmpty  { info[MPMediaItemPropertyAlbumTitle] = track.album  }

        if let img = currentArtwork
        {
            info[MPMediaItemPropertyArtwork] =
                MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
