import AVFoundation
import ExpoModulesCore

public class AudioController {
    var audioEngine: AVAudioEngine?
    var audioPlayerNode: AVAudioPlayerNode?
    
    private let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)
    
    // Two buffer queues for alternating playback, storing tuples of buffers and promises
    private var bufferQueueA: [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock)] = []
    private var bufferQueueB: [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock)] = []
    private let bufferAccessQueue = DispatchQueue(label: "com.kinexpoaudiostream.bufferAccessQueue") // Serial queue for thread-safe buffer access
    
    private var isPlayingQueueA: Bool = false // Indicates which queue is currently in use for playback
    
    init() {
        do {
            try setupAudioComponentsAndStart()
            setupNotifications()
        } catch {
            print("Failed to init")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Audio Setup
    
    private func activateAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func deactivateAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
    }
    
    private func setupAudioPlayerNode() {
        if let engine = audioEngine {
            audioPlayerNode = AVAudioPlayerNode()
            engine.attach(audioPlayerNode!)
        }
    }
    
    private func connectNodes() {
        if let engine = audioEngine, let playerNode = audioPlayerNode {
//            let format = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.connect(playerNode, to: engine.mainMixerNode, format: self.audioFormat)
        }
    }
    
    private func safeStartEngine() throws {
        if let engine = audioEngine, !engine.isRunning {
            try engine.start()
        } else if audioEngine == nil {
            setupAudioEngine()
            setupAudioPlayerNode()
            connectNodes()
            try audioEngine?.start()
        }
    }
    
    private func stopAndInvalidate() {
        audioEngine?.stop()
        audioEngine = nil
        audioPlayerNode = nil
    }
    
    private func setupAudioComponentsAndStart() throws {
        do {
            setupAudioEngine()
            setupAudioPlayerNode()
            connectNodes()
            try safeStartEngine()
        } catch {
            print("Failed to reset and start audio components: \(error.localizedDescription)")
        }
    }
    
    
    // MARK: - Notification Setup
    
    private func setupNotifications() {
        let audioSession = AVAudioSession.sharedInstance()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption), name: AVAudioSession.interruptionNotification, object: audioSession)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: audioSession)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMediaServicesWereLost), name: AVAudioSession.mediaServicesWereLostNotification, object: audioSession)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMediaServicesWereReset), name: AVAudioSession.mediaServicesWereResetNotification, object: audioSession)
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionDidChangeFocus), name: AVAudioSession.silenceSecondaryAudioHintNotification, object: AVAudioSession.sharedInstance())
        
        
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        if type == .began {
            // Audio has been interrupted
            audioPlayerNode?.pause()
            print("Audio session was interrupted.")
        } else if type == .ended {
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                // Attempt to reactivate the session and resume playing
                do {
                    try activateAudioSession()
                    audioPlayerNode?.play()
                    print("Resuming audio after interruption.")
                } catch {
                    print("Failed to reactivate audio session after interruption: \(error.localizedDescription)")
                }
            } else {
                print("Interruption ended without a resume option.")
            }
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
            case .oldDeviceUnavailable:
                audioPlayerNode?.pause()
                print("Headphones were unplugged.")
            case .newDeviceAvailable:
                // Resume playback if appropriate
            audioPlayerNode?.play()
            default:
                break
            }
    }
    
    @objc private func handleMediaServicesWereLost(notification: Notification) {
        stopAndInvalidate()
    }
    
    @objc private func handleMediaServicesWereReset(notification: Notification) {
        stopAndInvalidate()
        do {
            try setupAudioComponentsAndStart()
        } catch {
            print("Failed to handleMediaServicesWereReset: \(error.localizedDescription)")
        }
    }
    
    @objc func audioSessionDidChangeFocus(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue) else { return }
        
        if type == .begin {
            // Another app is asking for audio focus
            safePause()
        } else {
            // Focus returned to your app
            safePlay()
        }
    }
    
    @objc private func appDidBecomeActive(notification: Notification) {
        // Attempt to regain control over the audio session and restart playback if needed
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
            if let playerNode = audioPlayerNode, !audioEngine!.isRunning {
                try safeStartEngine()
                playerNode.play()  // Resume playing only if it makes sense to do so
            }
        } catch {
            print("Failed to activate audio session on app activation: \(error.localizedDescription)")
        }
    }
    
    // Adjust usage based on app lifecycle or specific user actions
    @objc func appWillResignActive(notification: Notification) {
        try? deactivateAudioSession()
    }
    
    // MARK: - Playback controls
    
    
    private func safePause() {
        if let node = audioPlayerNode, let engine = audioEngine, engine.isRunning {
            node.pause()
        } else {
            print("Cannot pause: Engine is not running or node is unavailable.")
        }
    }

    public func pause(promise: Promise) {
        DispatchQueue.main.async {
            self.safePause()
            promise.resolve(nil)
        }
    }
    
    private func safeStop() {
        if let node = audioPlayerNode, let engine = audioEngine, engine.isRunning {
            node.stop()
        } else {
            print("Cannot stop: Engine is not running or node is unavailable.")
        }
    }

    
    public func stop(promise: Promise) {
        DispatchQueue.main.async {
            self.safeStop()  // Stop the audio player node
            do {
                try self.deactivateAudioSession()  // Deactivate the session
                self.bufferQueueA.removeAll()
                self.bufferQueueB.removeAll()
                promise.resolve(nil)
            } catch {
                promise.reject("PLAYBACK_STOP", "Failed to deactivate audio session: \(error.localizedDescription)")
                print("Failed to deactivate audio session: \(error.localizedDescription)")
            }
        }
    }

    
    private func safePlay() {
        if let node = audioPlayerNode, let engine = audioEngine, engine.isRunning {
            node.play()
        } else {
            print("Engine is not running or node is unavailable.")
        }
    }
    
    func play(promise: Promise?) {
        DispatchQueue.main.async {
            // Ensure that the audio engine and nodes are set up
            if self.audioEngine == nil || self.audioPlayerNode == nil || !self.audioEngine!.isRunning {
                do {
                    try self.setupAudioComponentsAndStart()
                } catch {
                    print("Failed to setupAudioComponentsAndStart: \(error.localizedDescription)")
                }
            }
            
            // Attempt to activate the audio session and play
            do {
                try self.activateAudioSession()
                self.safePlay()
                promise?.resolve(nil)
            } catch {
                promise?.reject("PLAYBACK_PLAY", "Failed to activate audio session or play audio: \(error.localizedDescription)")
                print("Failed to activate audio session or play audio: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func setVolume(_ volume: Float, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        let clampedVolume = max(0, min(volume, 100)) / 100.0 // Normalize and clamp to [0, 1]
        
        DispatchQueue.main.async {
            self.audioPlayerNode?.volume = clampedVolume
            resolver(nil)
        }
    }
    
    // MARK: - helper methods
    
    public func removeRIFFHeaderIfNeeded(from audioData: Data) -> Data? {
        let headerSize = 44 // The "RIFF" header is 44 bytes
        guard audioData.count > headerSize, audioData.starts(with: "RIFF".data(using: .ascii)!) else {
            return audioData
        }
        return audioData.subdata(in: headerSize..<audioData.count)
    }
    
    public func convertPCMDataToBuffer(_ pcmData: Data) -> AVAudioPCMBuffer? {
        // Prepare buffer for Float32 samples
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: self.audioFormat!, frameCapacity: AVAudioFrameCount(pcmData.count / 2)) else {
            print("Failed to create audio buffer.")
            return nil
        }
        
        var int16Samples = [Int16](repeating: 0, count: pcmData.count / 2)
        int16Samples.withUnsafeMutableBytes { buffer in
            pcmData.copyBytes(to: buffer)
        }
        
        // Conversion to Float32
        let floatSamples = int16Samples.map { Float($0) / 32768.0 }
        
        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        if let channelData = pcmBuffer.floatChannelData {
            for i in 0..<floatSamples.count {
                channelData.pointee[i] = floatSamples[i]
            }
        }
        
        return pcmBuffer
    }
    
    @objc func streamRiff16Khz16BitMonoPcmChunk(_ chunk: String, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        guard let audioData = Data(base64Encoded: chunk),
              let pcmData = self.removeRIFFHeaderIfNeeded(from: audioData),
              let pcmBuffer = self.convertPCMDataToBuffer(pcmData) else {
            rejecter("ERR_DECODE_AUDIO", "Failed to process audio chunk", nil)
            return
        }
        
        print("pcmBuffer size: \(pcmBuffer.frameLength)")
        
        self.bufferAccessQueue.async {
            let bufferTuple = (buffer: pcmBuffer, promise: resolver)
            if self.isPlayingQueueA {
                // Directly append to bufferQueueB if isPlayingQueueA is true
                self.bufferQueueB.append(bufferTuple)
            } else {
                // Otherwise, append to bufferQueueA
                self.bufferQueueA.append(bufferTuple)
            }
            
            self.switchQueuesAndPlay()
        }
    }
    
    private func switchQueuesAndPlay() {
        // Clear the queue that just finished playing
        self.bufferAccessQueue.async {
            if self.isPlayingQueueA {
                self.bufferQueueA.removeAll()
            } else {
                self.bufferQueueB.removeAll()
            }
        }
        
        self.isPlayingQueueA.toggle() // Switch queues
        
        // Schedule buffers from the new current queue for playback
        let currentQueue = self.currentQueue()
        for (buffer, promise) in currentQueue {
            self.audioPlayerNode!.scheduleBuffer(buffer) {
                promise(nil)
            }
        }
        self.play(promise: nil)
    }
    
    private func currentQueue() -> [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock)] {
        return self.isPlayingQueueA ? self.bufferQueueA : self.bufferQueueB
    }
}
