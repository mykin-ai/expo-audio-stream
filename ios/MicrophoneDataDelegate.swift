protocol MicrophoneDataDelegate: AnyObject {
    func onMicrophoneData(_ microphoneData: Data, _ microphoneData16kHz: Data)
}
