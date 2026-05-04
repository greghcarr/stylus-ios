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

    private weak var queue: PlayQueue?

    init(queue: PlayQueue? = nil)
    {
        self.queue = queue
        engine.attach(node)
        configureSession()
    }

    func attach(queue: PlayQueue)
    {
        self.queue = queue
    }

    private func configureSession()
    {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        try? session.setActive(true)
    }

    // MARK: - Playback control

    func play(_ track: Track)
    {
        stopInternal()

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

            engine.connect(node, to: engine.mainMixerNode, format: f.processingFormat)

            scheduleAndPlay(startFrame: 0)

            currentTrack = track
            isPlaying    = true
            startTimer()
        }
        catch
        {
            print("AudioPlayer: failed to load \(track.filePath): \(error)")
            currentTrack = nil
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
        node.pause()
        isPlaying = false
        stopTimer()
    }

    func resume()
    {
        guard !isPlaying, currentTrack != nil else { return }
        if !engine.isRunning { try? engine.start() }
        node.play()
        isPlaying = true
        startTimer()
    }

    func stop()
    {
        stopInternal()
        currentTrack = nil
        currentTime  = 0
        duration     = 0
    }

    private func stopInternal()
    {
        scheduleGen &+= 1     // invalidate any pending .dataPlayedBack callback
        node.stop()
        if engine.isRunning { engine.stop() }
        isPlaying = false
        file      = nil
        stopTimer()
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
        playNext()
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
