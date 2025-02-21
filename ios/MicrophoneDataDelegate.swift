protocol MicrophoneDataDelegate: AnyObject {
    func onMicrophoneData(_ microphoneData: Data, _ soundLevel: Float?)
}
