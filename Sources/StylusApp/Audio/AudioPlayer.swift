import AVFoundation
import Combine

// AVAudioEngine + AVAudioPlayerNode based player. Picked over AVAudioPlayer
// because the eventual roadmap (DJ mode, gapless, level meters, EQ /
// pitch-shift, two-deck mixing) needs the engine graph; AVAudioPlayer can't
// scale into any of that.
//
// Phase 3a scope:
//   - Single playback at a time, auto-advance through the attached PlayQueue
//   - Play / pause / resume / stop / seek
//   - currentTime + duration as @Published for UI scrubber binding
//
// Deferred:
//   - Level metering tap (Phase 3.5 / DJ groundwork)
//   - Gapless next-track scheduling (DJ phase)
//   - Effects nodes (DJ phase)
//   - Route change / interruption handling (Phase 3c)
@MainActor
final class AudioPlayer: ObservableObject
{
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying:    Bool         = false
    @Published private(set) var currentTime:  TimeInterval = 0
    @Published private(set) var duration:     TimeInterval = 0

    private let engine = AVAudioEngine()
    private let node   = AVAudioPlayerNode()

    private var file:        AVAudioFile?
    private var sampleRate:  Double               = 44_100
    private var totalFrames: AVAudioFramePosition = 0
    // Where the current schedule started, used to compute absolute
    // currentTime when summed with the node's playerTime since play().
    private var seekFrame:   AVAudioFramePosition = 0
    // Bumped on every schedule-changing event (new schedule, stop). The
    // .dataPlayedBack completion handler captures the current value at
    // schedule time and ignores its fire if the generation has moved on,
    // because iOS sometimes fires the old schedule's completion after we've
    // cancelled it via node.stop(), which would otherwise cascade through
    // the queue (each playNext stops the previous schedule, the previous
    // schedule's completion then triggers another playNext, and so on).
    private var scheduleGen: UInt64 = 0
    private var timer:       Timer?
    // Cached format of the node -> mainMixer connection. Used by
    // play(_:) to skip engine.connect when the next track has the
    // same sample rate + channel count as the previous one. Most
    // libraries are mostly 44.1 kHz stereo, so this elides the
    // reconnect on the typical track switch.
    private var lastConnectedFormat: AVAudioFormat?
    // In-flight volume ramp for the user-initiated track switch
    // fade-out (see performFadeOut). Cancelled when a new switch
    // arrives mid-fade so the latest press takes precedence.
    private var fadeTask: Task<Void, Never>?

    // Length of the volume ramp applied before tearing down the
    // current track on a user-initiated switch. 20 ms is short
    // enough to feel instantaneous but long enough to clear a
    // mid-amplitude sample down to silence in ~8 sub-step
    // increments without each sub-step itself being audible.
    private static let switchFadeDuration: TimeInterval = 0.020
    private static let switchFadeSteps:    Int          = 8

    // External listener (NowPlayingController) hooks this to refresh
    // MPNowPlayingInfoCenter on every meaningful state change. The system
    // extrapolates currentTime from (elapsed, rate) so we only fire on
    // play / pause / resume / stop / seek, not on every timer tick.
    var onPlaybackStateChanged: (() -> Void)?

    private weak var queue: PlayQueue?

    init(queue: PlayQueue? = nil)
    {
        self.queue = queue
        engine.attach(node)
        configureSession()
        registerSessionObservers()
    }

    func attach(queue: PlayQueue)
    {
        self.queue = queue
    }

    private func configureSession()
    {
        let session = AVAudioSession.sharedInstance()
        // .playback gives us the standard "music app" priority so the
        // system doesn't silence us under Silent switch / lock. .default
        // mode is the right choice for general A/V playback (no speech
        // ducking, no measurement-mode artefacts).
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // Registers handlers for the three AVAudioSession lifecycle
    // notifications a music app needs to react to:
    //   - interruptionNotification: phone call, alarm, another app's
    //     audio session takes over. We pause on .began, optionally
    //     resume on .ended if iOS hints we should.
    //   - routeChangeNotification: AirPods unplugged / Bluetooth
    //     disconnected. iOS pauses audio output but doesn't tell our
    //     engine; we mirror Apple Music's behaviour and pause so
    //     audio doesn't suddenly blast out the phone speaker.
    //   - mediaServicesWereResetNotification: the audio server
    //     restarted (rare; recovery from a system audio crash). Our
    //     engine + node references are now stale and need to be
    //     rebuilt before any further playback.
    private func registerSessionObservers()
    {
        let nc = NotificationCenter.default

        nc.addObserver(forName:  AVAudioSession.interruptionNotification,
                       object:   nil,
                       queue:    .main)
        { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleInterruption(note)
            }
        }

        nc.addObserver(forName:  AVAudioSession.routeChangeNotification,
                       object:   nil,
                       queue:    .main)
        { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(note)
            }
        }

        nc.addObserver(forName:  AVAudioSession.mediaServicesWereResetNotification,
                       object:   nil,
                       queue:    .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        }
    }

    private func handleInterruption(_ note: Notification)
    {
        guard let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type    = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type
        {
        case .began:
            // Pause via our normal path so isPlaying flips to false,
            // the timer stops, NowPlayingController publishes
            // (elapsed, rate=0), and the lock screen / Control Center
            // stay aligned with the silent reality.
            if isPlaying { pause() }

        case .ended:
            // Resume only when the system hints we should -- some
            // interruptions (e.g. phone call) end with the option set;
            // others (Siri "Hey, what's the weather") usually don't,
            // and forcing a resume would clash with the user's intent.
            let optsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let opts    = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
            if opts.contains(.shouldResume), currentTrack != nil
            {
                try? AVAudioSession.sharedInstance().setActive(true)
                resume()
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification)
    {
        guard let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason    = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
        else { return }

        // Only the "old device unavailable" reason warrants a pause:
        // the user just unplugged headphones or AirPods walked out of
        // range, and continuing through the phone speaker would be
        // surprising. Other reasons (new device available, category
        // change) don't need our intervention.
        if reason == .oldDeviceUnavailable, isPlaying { pause() }
    }

    private func handleMediaServicesReset()
    {
        // Rare but documented: the audio server restarted under us.
        // Anything we held against the old server is dead; tear down
        // and let the next play() rebuild from scratch. The user will
        // see the track stop, which is the least-bad option short of
        // a full engine rebuild here (the engine + node would need
        // reconstruction, which we can't do safely from a notification
        // callback without coordinating with whatever's currently in
        // flight).
        stop()
        configureSession()
    }

    // MARK: - Playback control

    // fadeOutPrevious: true on user-initiated switches (next / prev /
    // tap-to-play another track), false on auto-advance from a
    // natural track end (the previous track is already at silent
    // end, no fade needed and we'd just delay the next track's
    // start). Defaults to true so external callers get the safer
    // behaviour without thinking about it.
    func play(_ track: Track, fadeOutPrevious: Bool = true)
    {
        // Cancel any in-flight fade so a rapid double-tap on next
        // doesn't stack two fades on top of each other. The new
        // press takes precedence; whatever volume the previous fade
        // had already reached is the starting volume for this one
        // (or for playImmediate's reset).
        fadeTask?.cancel()
        fadeTask = nil

        let needsFade = fadeOutPrevious
                     && isPlaying
                     && currentTrack != nil
                     && currentTrack?.filePath != track.filePath

        guard needsFade else
        {
            playImmediate(track)
            return
        }

        fadeTask = Task
        { @MainActor [weak self] in
            guard let self = self else { return }
            await self.performSwitchFade()
            if Task.isCancelled { return }
            self.fadeTask = nil
            self.playImmediate(track)
        }
    }

    private func playImmediate(_ track: Track)
    {
        // Reset the node's volume in case a previous fade left it
        // lowered (cancelled mid-ramp, or this immediate path is
        // following a completed fade). Without this, a track that
        // started right after a cancelled fade would play quietly
        // until the next user switch.
        node.volume = 1.0

        // Tear down the schedule but leave the engine RUNNING across
        // the track boundary. Stopping and restarting the engine for
        // every track switch causes the audio output device on the
        // speaker hardware to briefly disengage and re-engage -- the
        // "click between songs" the user heard. Keeping the engine
        // alive across track changes removes that click; the brief
        // silence between tracks comes from the node having no
        // scheduled buffer, not from the output device dropping out.
        stopInternal(tearDownEngine: false)

        let url = URL(fileURLWithPath: track.filePath)
        do
        {
            let f = try AVAudioFile(forReading: url)
            file        = f
            sampleRate  = f.processingFormat.sampleRate
            totalFrames = f.length
            seekFrame   = 0
            duration    = sampleRate > 0 ? Double(totalFrames) / sampleRate : 0
            currentTime = 0

            // Skip the connect when the new track has the same format
            // as the last one. AVAudioEngine.connect during playback
            // can produce a small click of its own as the mixer
            // re-establishes the connection; this elision keeps the
            // typical 44.1 kHz-stereo -> 44.1 kHz-stereo transition
            // glitch-free.
            if needsReconnect(for: f.processingFormat)
            {
                engine.connect(node,
                               to:     engine.mainMixerNode,
                               format: f.processingFormat)
                lastConnectedFormat = f.processingFormat
            }

            scheduleAndPlay(startFrame: 0)

            currentTrack = track
            isPlaying    = true
            startTimer()
            onPlaybackStateChanged?()
        }
        catch
        {
            print("AudioPlayer: failed to load \(track.filePath): \(error)")
            currentTrack = nil
            onPlaybackStateChanged?()
        }
    }

    // Linear volume ramp from the node's current level down to 0
    // over `switchFadeDuration` in `switchFadeSteps` sub-steps.
    // Stepped (rather than continuous) because AVAudioPlayerNode
    // doesn't expose a built-in ramp; 8 steps over 20 ms keeps each
    // sub-step's amplitude jump well below the click threshold.
    private func performSwitchFade() async
    {
        let stepNanos = UInt64((Self.switchFadeDuration
                                / Double(Self.switchFadeSteps))
                               * 1_000_000_000)
        let startVolume = node.volume

        for i in 1...Self.switchFadeSteps
        {
            try? await Task.sleep(nanoseconds: stepNanos)
            if Task.isCancelled { return }
            let remaining = Float(Self.switchFadeSteps - i)
                          / Float(Self.switchFadeSteps)
            node.volume = startVolume * remaining
        }
    }

    func togglePlayPause()
    {
        guard currentTrack != nil else { return }
        if isPlaying { pause() } else { resume() }
    }

    func pause()
    {
        guard isPlaying else { return }
        // Refresh currentTime from the renderer's actual sample position
        // BEFORE flipping isPlaying / pausing the node, so the lock screen
        // and Control Center receive the true paused offset rather than
        // the 0.25 s timer's last (potentially stale) value. Without this,
        // MPNowPlayingInfoCenter's elapsed lags reality by up to a tick
        // and on resume the system extrapolates forward from the stale
        // point while the audio plays from the real point -- they drift.
        tickCurrentTime()
        node.pause()
        isPlaying = false
        stopTimer()
        onPlaybackStateChanged?()
    }

    func resume()
    {
        guard !isPlaying, currentTrack != nil else { return }
        if !engine.isRunning { try? engine.start() }
        node.play()
        isPlaying = true
        // Same boundary capture as pause(): the node's playerTime stays
        // valid across pause, so the first tick post-resume returns the
        // paused position (= where playback will actually resume from).
        // Pushing this fresh value to MPNowPlayingInfoCenter before the
        // timer's first tick lands keeps the lock screen aligned with
        // the audio from the very first sample of the resume.
        tickCurrentTime()
        startTimer()
        onPlaybackStateChanged?()
    }

    func stop()
    {
        stopInternal()
        currentTrack = nil
        currentTime  = 0
        duration     = 0
        onPlaybackStateChanged?()
    }

    // tearDownEngine: pass false on track-to-track transitions to leave
    // the engine running across the boundary (avoids the speaker-
    // hardware click). Pass true (the default) when fully ending
    // playback so the audio session can release its hold on the
    // output route.
    private func stopInternal(tearDownEngine: Bool = true)
    {
        scheduleGen &+= 1     // invalidate any pending .dataPlayedBack callback
        node.stop()
        if tearDownEngine && engine.isRunning { engine.stop() }
        isPlaying = false
        file      = nil
        stopTimer()
    }

    // True iff the new track's format differs from whatever the
    // node -> mainMixer connection is currently configured for.
    // Compares sample rate + channel count rather than relying on
    // AVAudioFormat equality, which is over-strict (would trip on
    // bit-depth differences that the mixer handles transparently).
    private func needsReconnect(for newFormat: AVAudioFormat) -> Bool
    {
        guard let last = lastConnectedFormat else { return true }
        return last.sampleRate   != newFormat.sampleRate
            || last.channelCount != newFormat.channelCount
    }

    func seek(to seconds: TimeInterval)
    {
        guard file != nil, sampleRate > 0 else { return }
        let clamped = min(max(0, seconds), duration)
        let frame   = AVAudioFramePosition(clamped * sampleRate)
        let wasPlaying = isPlaying
        node.stop()
        scheduleAndPlay(startFrame: frame)
        if !wasPlaying { node.pause(); isPlaying = false; stopTimer() }
        currentTime = clamped
        onPlaybackStateChanged?()
    }

    func playNext()
    {
        guard let next = queue?.advance() else { stop(); return }
        play(next)
    }

    // Mimics the iOS music-app convention: < 3 s into the track restarts it,
    // anything later goes to the previous queue entry.
    func playPrev()
    {
        if currentTime > 3
        {
            seek(to: 0)
        }
        else if let prev = queue?.goBack()
        {
            play(prev)
        }
        else
        {
            seek(to: 0)
        }
    }

    // MARK: - Internal

    private func scheduleAndPlay(startFrame: AVAudioFramePosition)
    {
        guard let f = file else { return }
        let remaining = totalFrames - startFrame
        guard remaining > 0 else { return }

        scheduleGen &+= 1
        let myGen = scheduleGen

        node.scheduleSegment(
            f,
            startingFrame:          startFrame,
            frameCount:             AVAudioFrameCount(remaining),
            at:                     nil,
            completionCallbackType: .dataPlayedBack
        )
        { [weak self] _ in
            // completionHandler fires on a background thread; bounce onto
            // MainActor so we can touch @Published state safely. Drop the
            // event if a newer schedule has superseded this one (see the
            // scheduleGen comment near its declaration).
            Task { @MainActor [weak self] in
                guard let self = self, myGen == self.scheduleGen else { return }
                self.handleTrackEnd()
            }
        }

        if !engine.isRunning { try? engine.start() }
        node.play()
        seekFrame = startFrame
    }

    private func handleTrackEnd()
    {
        // Only auto-advance if we're at end of the file. Pause / stop /
        // seek calls cancel the buffer and would otherwise spuriously fire
        // .dataPlayedBack with seekFrame ahead of where we paused.
        guard isPlaying else { return }
        // advanceForAutoFinish encapsulates repeat-mode behaviour:
        //   - repeatMode == .one: returns currentTrack (replay)
        //   - repeatMode == .all: wraps to index 0 at end of queue
        //   - repeatMode == .off: returns nil at end of queue (stop)
        // Skip the user-switch fade-out either way (the track has
        // already played to its silent end, fading would just delay
        // the next track's start without any audible benefit).
        if let next = queue?.advanceForAutoFinish()
        {
            play(next, fadeOutPrevious: false)
        }
        else
        {
            stop()
        }
    }

    // MARK: - currentTime ticker

    private func startTimer()
    {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true)
        { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickCurrentTime() }
        }
    }

    private func stopTimer()
    {
        timer?.invalidate()
        timer = nil
    }

    private func tickCurrentTime()
    {
        guard isPlaying,
              let lastRender = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: lastRender)
        else { return }
        let elapsedSinceSchedule = Double(playerTime.sampleTime) / playerTime.sampleRate
        currentTime = min(duration, Double(seekFrame) / sampleRate + elapsedSinceSchedule)
    }
}
