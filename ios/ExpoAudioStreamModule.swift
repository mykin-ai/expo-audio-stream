import Foundation
import AVFoundation
import ExpoModulesCore

public class ExpoAudioStreamModule: Module {
    private let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var audioSession = AVAudioSession.sharedInstance()
    
    // Two buffer queues for alternating playback, storing tuples of buffers and promises
    private var bufferQueueA: [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock)] = []
    private var bufferQueueB: [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock)] = []
    private let bufferAccessQueue = DispatchQueue(label: "com.kinexpoaudiostream.bufferAccessQueue") // Serial queue for thread-safe buffer access
    
    private var isPlayingQueueA: Bool = false // Indicates which queue is currently in use for playback
    private var anotherAppPlaying: Bool = false
    private var isAudioEngineSetup: Bool = false
    private var isAudioSessionSetup: Bool = false
    
    private func setupAudioEngine() {
            self.playerNode = AVAudioPlayerNode()
            self.audioEngine = AVAudioEngine()
            self.audioEngine.attach(self.playerNode)
            self.audioEngine.connect(self.playerNode, to: self.audioEngine.mainMixerNode, format: self.audioFormat)
            self.playerNode.volume = 1.0
            self.isAudioEngineSetup = true
    }
    
    private func configureAudioSession() {
            do {
                self.audioSession = AVAudioSession.sharedInstance()
                try self.audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
                try self.audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                self.isAudioSessionSetup = true
            } catch {
                print("Error configuring audio session: \(error)")
            }
    }
    
    func restoreAudioSession() {
        // Stop or pause all audio playback and recording
        self.audioEngine.stop()
        self.audioEngine.disconnectNodeOutput(self.audioEngine.mainMixerNode)

        // Wait for the audio engine to fully stop before deactivating the audio session
        while self.audioEngine.isRunning {
            // Wait for the audio engine to stop
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Introduce a delay before deactivating the audio session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                // Deactivate the audio session
                try self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                self.setupAudioEngine()
                self.configureAudioSession()
            } catch {
                print("Error deactivating or reactivating audio session: \(error.localizedDescription)")
            }
        }
    }

    private func startEngineAndNodeIfNeeded() {
        do {
            if !self.audioEngine.isRunning {
                self.audioEngine.prepare()
                try self.audioEngine.start()
            }

            if !self.playerNode.isPlaying {
                self.playerNode.play()
            }
        } catch {
            self.restoreAudioSession()
            print("Error starting audio engine: \(error)")
        }
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
            
            // Check if it's time to switch queues and initiate playback
            if self.playerNode.isPlaying == false || self.currentQueue().isEmpty {
                self.switchQueuesAndPlay()
            }
        }
    }
    
    private func switchQueuesAndPlay() {
        if !self.isAudioEngineSetup {
            self.setupAudioEngine()
        }
        
        if !self.isAudioSessionSetup {
            self.configureAudioSession()
        }

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
            self.playerNode.scheduleBuffer(buffer) { [weak self] in
                self?.onBufferCompletion(promise)
            }
        }
        
        
        // Ensure the audio engine and player node are running
        self.startEngineAndNodeIfNeeded()
        
        
    }
    
    private func currentQueue() -> [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock)] {
        return self.isPlayingQueueA ? self.bufferQueueA : self.bufferQueueB
    }
    
    private func onBufferCompletion(_ promise: RCTPromiseResolveBlock) {
        //Resolve the promise when the buffer finishes playing
        promise(nil)
    }
    
    
    private func removeRIFFHeaderIfNeeded(from audioData: Data) -> Data? {
        let headerSize = 44 // The "RIFF" header is 44 bytes
        guard audioData.count > headerSize, audioData.starts(with: "RIFF".data(using: .ascii)!) else {
            return audioData
        }
        return audioData.subdata(in: headerSize..<audioData.count)
    }
    
    // Revised PCM Data to Buffer conversion
    private func convertPCMDataToBuffer(_ pcmData: Data) -> AVAudioPCMBuffer? {
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
    
    @objc func setVolume(_ volume: Float, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        let clampedVolume = max(0, min(volume, 100)) / 100.0 // Normalize and clamp to [0, 1]
        
        DispatchQueue.main.async {
            self.playerNode.volume = clampedVolume
            resolver(nil)
        }
    }
    
    private func pausePlayback(promise: Promise) {
        DispatchQueue.main.async {
            self.playerNode.pause()
            promise.resolve(nil)
        }
    }
    
    private func startPlayback(promise: Promise) {
        DispatchQueue.main.async {
            if !self.audioEngine.isRunning {
                do {
                    try self.audioEngine.start()
                } catch {
                    promise.reject("ERR_STARTING_ENGINE", "Failed to start audio engine: \(error.localizedDescription)")
                    return
                }
            }
            self.playerNode.play()
            promise.resolve(nil)
        }
    }
    
    private func stopPlayback(promise: Promise) {
        DispatchQueue.main.async {
            self.playerNode.stop()
            self.bufferQueueA.removeAll()
            self.bufferQueueB.removeAll()
            promise.resolve(nil)
        }
    }
    
    private func monitorAudioRouteChanges() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: nil) { [weak self] notification in
            self?.handleAudioSessionRouteChange(notification: notification)
        }
    }
    
    func monitorAudioSessionNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    
    @objc private func handleAudioSessionRouteChange(notification: Notification) {
        print("Route change detected")
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        print("Route change reason: \(reason)")
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            print("Updating audio route due to device availability changes")
            self.updateAudioRoute()
        default: break
        }
    }
    
    @objc func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            self.anotherAppPlaying = true
        case .ended:
            self.anotherAppPlaying = false
            self.configureAudioSession()
        }
    }
    
    private func updateAudioRoute() {
        let audioSession = AVAudioSession.sharedInstance()
        let headphonesConnected = audioSession.currentRoute.outputs.contains { $0.portType == .headphones || $0.portType == .bluetoothA2DP }
        try? audioSession.overrideOutputAudioPort(headphonesConnected ? .none : .speaker)
        print("updateAudioRoute: \(headphonesConnected)")
        print("audioSession.currentRoute.outputs: \(audioSession.currentRoute.outputs)")
    }
    
    
    public func definition() -> ModuleDefinition {
        Name("ExpoAudioStream")
        
        AsyncFunction("streamRiff16Khz16BitMonoPcmChunk") { (base64chunk: String, promise: Promise) in
            self.streamRiff16Khz16BitMonoPcmChunk(base64chunk, resolver: { _ in
                promise.resolve(nil)
            }, rejecter: { code, message, error in
                promise.reject(code ?? "ERR_UNKNOWN", message ?? "Unknown error")
            })
        }
        
        AsyncFunction("setVolume") { (volume: Float, promise: Promise) in
            self.setVolume(volume, resolver: { _ in
                promise.resolve(nil)
            }, rejecter: { code, message, error in
                promise.reject(code ?? "ERR_VOLUME_ERROR", message ?? "Error setting volume")
            })
        }
        
        AsyncFunction("pause") { promise in
            self.pausePlayback(promise: promise)
        }
        
        AsyncFunction("start") { promise in
            self.startPlayback(promise: promise)
        }
        
        AsyncFunction("stop") { promise in
            self.stopPlayback(promise: promise)
        }
        
        OnCreate {
            self.monitorAudioRouteChanges()
            self.monitorAudioSessionNotifications()
            self.updateAudioRoute()
        }
    }
}
