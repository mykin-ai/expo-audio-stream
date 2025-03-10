import AVFoundation

protocol SoundPlayerDelegate: AnyObject {
    func onSoundChunkPlayed(_ isFinal: Bool)
    func onSoundStartedPlaying()
    func onDeviceReconnected(_ reason: AVAudioSession.RouteChangeReason)
}
