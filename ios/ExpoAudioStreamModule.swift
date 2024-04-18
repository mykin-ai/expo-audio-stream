import Foundation
import AVFoundation
import ExpoModulesCore

public class ExpoAudioStreamModule: Module {
    private let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var audioSessionCategory: AVAudioSession.Category = .playback
    private var audioSessionMode: AVAudioSession.Mode = .default
    
    // Two buffer queues for alternating playback, storing tuples of buffers and promises
    private var bufferQueueA: [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock)] = []
    private var bufferQueueB: [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock)] = []
    private let bufferAccessQueue = DispatchQueue(label: "com.kinexpoaudiostream.bufferAccessQueue") // Serial queue for thread-safe buffer access
    
    private var isPlayingQueueA: Bool = false // Indicates which queue is currently in use for playback
    
    private func setupAudioEngine() {
        self.audioEngine.attach(self.playerNode)
        self.audioEngine.connect(self.playerNode, to: self.audioEngine.mainMixerNode, format: self.audioFormat)
        self.playerNode.volume = 1.0
        do {
            try self.audioEngine.start()
            self.configureAudioSession()
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(self.audioSessionCategory, mode: self.audioSessionMode, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Error configuring audio session: \(error)")
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
        // Clear the queue that just finished playing
        self.bufferAccessQueue.async {
            if self.isPlayingQueueA {
                self.bufferQueueA.removeAll()
            } else {
                self.bufferQueueB.removeAll()
            }
        }
        
        self.isPlayingQueueA.toggle() // Switch queues
        
        // Ensure the audio engine and player node are running
        self.startEngineAndNodeIfNeeded()
        
        // Schedule buffers from the new current queue for playback
        let currentQueue = self.currentQueue()
        for (buffer, promise) in currentQueue {
            self.playerNode.scheduleBuffer(buffer) { [weak self] in
                self?.onBufferCompletion(promise)
            }
        }
    }
    
    private func currentQueue() -> [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock)] {
        return self.isPlayingQueueA ? self.bufferQueueA : self.bufferQueueB
    }
    
    private func onBufferCompletion(_ promise: RCTPromiseResolveBlock) {
        //Resolve the promise when the buffer finishes playing
        promise(nil)
    }
    
    private func startEngineAndNodeIfNeeded() {
        if !self.audioEngine.isRunning {
            do {
                try self.audioEngine.start()
            } catch {
                print("Error starting audio engine: \(error)")
            }
        }
        
        if !self.playerNode.isPlaying {
            self.playerNode.play()
        }
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
            self.setupAudioEngine()
        }
    }
}