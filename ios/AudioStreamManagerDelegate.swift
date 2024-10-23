protocol AudioStreamManagerDelegate: AnyObject {
    func audioStreamManager(_ manager: AudioSessionManager, didReceiveAudioData data: Data, recordingTime: TimeInterval, totalDataSize: Int64)
}
