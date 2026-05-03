import AVFoundation
import Combine

final class AudioPlayer: NSObject, ObservableObject
{
    @Published private(set) var nowPlayingPath: String?

    private var player: AVAudioPlayer?

    override init()
    {
        super.init()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true)
    }

    func play(filePath: String)
    {
        let url = URL(fileURLWithPath: filePath)
        do
        {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            nowPlayingPath = filePath
        }
        catch
        {
            player = nil
            nowPlayingPath = nil
        }
    }

    func stop()
    {
        player?.stop()
        player = nil
        nowPlayingPath = nil
    }
}

extension AudioPlayer: AVAudioPlayerDelegate
{
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool)
    {
        nowPlayingPath = nil
        self.player = nil
    }
}
