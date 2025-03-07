import AVFoundation
import ExpoModulesCore

class SoundPlayer {
    weak var delegate: SoundPlayerDelegate?
    private var audioEngine: AVAudioEngine!
    private var audioPlayerNode: AVAudioPlayerNode!
    
    private var audioPlayer: AVAudioPlayer?
    
    private let bufferAccessQueue = DispatchQueue(label: "com.expoaudiostream.bufferAccessQueue")
    
    private var audioQueue: [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock, turnId: String)] = []  // Queue for audio segments
    // needed to track segments in progress in order to send playbackevents properly
    private var segmentsLeftToPlay: Int = 0
    private var isPlaying: Bool = false  // Tracks if audio is currently playing
    private var isInterrupted: Bool = false
    public var isAudioEngineIsSetup: Bool = false
    
    // specific turnID to ignore sound events
    internal let suspendSoundEventTurnId: String = "suspend-sound-events"
  
    private var audioPlaybackFormat: AVAudioFormat!
    private var config: SoundConfig
    
    init(config: SoundConfig = SoundConfig()) {
        self.config = config
        self.audioPlaybackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: config.sampleRate, channels: 1, interleaved: false)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    /// Handles audio route changes (e.g. headphones connected/disconnected)
    /// - Parameter notification: The notification object containing route change information
    @objc private func handleRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        Logger.debug("[SoundPlayer] Route is changed \(reason)")

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            if let node = audioPlayerNode, node.isPlaying {
                node.pause()
                node.stop()
            }
            
            do {
                try self.ensureAudioEngineIsSetup()
            } catch {
                Logger.debug("[SoundPlayer] Failed to setup audio engine: \(error.localizedDescription)")
            }
        case .categoryChange:
            Logger.debug("[SoundPlayer] Audio Session category changed")
        default:
            break
        }
    }
    
    /// Detaches and cleans up the existing audio player node from the engine
    private func detachOldAvNodesFromEngine() {
        Logger.debug("[SoundPlayer] Detaching old audio node")
        guard let playerNode = self.audioPlayerNode else { return }

        // Stop and detach the node
        if playerNode.isPlaying {
            Logger.debug("[SoundPlayer] Destroying audio node, player is playing, stopping it")
            playerNode.stop()
        }
        self.audioEngine.disconnectNodeOutput(playerNode)
        self.audioEngine.detach(playerNode)

        // Set to nil, ARC deallocates it if no other references exist
        self.audioPlayerNode = nil
    }
    
    /// Updates the audio configuration and reconfigures the audio engine
    /// - Parameter newConfig: The new configuration to apply
    /// - Throws: Error if audio engine setup fails
    public func updateConfig(_ newConfig: SoundConfig) throws {
        Logger.debug("[SoundPlayer] Updating configuration - sampleRate: \(newConfig.sampleRate), playbackMode: \(newConfig.playbackMode)")
        
        // Check if anything has changed
        let configChanged = newConfig.sampleRate != self.config.sampleRate ||
                           newConfig.playbackMode != self.config.playbackMode
        
        guard configChanged else {
            Logger.debug("[SoundPlayer] Configuration unchanged, skipping update")
            return
        }
        
        // Stop playback if active
        if let playerNode = self.audioPlayerNode, playerNode.isPlaying {
            playerNode.stop()
        }
        
        // Stop and reset engine if running
        if let engine = self.audioEngine, engine.isRunning {
            engine.stop()
            self.detachOldAvNodesFromEngine()
        }
        
        // Update configuration
        self.config = newConfig
        
        // Update format with new sample rate
        self.audioPlaybackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: newConfig.sampleRate, channels: 1, interleaved: false)
        
        // Reconfigure audio engine
        try self.ensureAudioEngineIsSetup()
    }
    
    /// Resets the audio configuration to default values and reconfigures the audio engine
    /// - Throws: Error if audio engine setup fails
    public func resetConfigToDefault() throws {
        Logger.debug("[SoundPlayer] Resetting configuration to default values")
        try updateConfig(SoundConfig.defaultConfig)
    }
    
    /// Sets up the audio engine and player node if not already configured
    /// - Throws: Error if audio engine setup fails
    public func ensureAudioEngineIsSetup() throws {
        // If engine exists, stop and detach nodes
        if let existingEngine = self.audioEngine {
            if existingEngine.isRunning {
                existingEngine.stop()
            }
            self.detachOldAvNodesFromEngine()
        }
        
        // Create new engine
        self.audioEngine = AVAudioEngine()
                    
        audioPlayerNode = AVAudioPlayerNode()
        if let playerNode = self.audioPlayerNode {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: self.audioPlaybackFormat)
            audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: self.audioPlaybackFormat)
            
            // Enable voice processing based on playback mode
            if config.playbackMode == .voiceProcessing || config.playbackMode == .conversation {
                try audioEngine.inputNode.setVoiceProcessingEnabled(true)
                try audioEngine.outputNode.setVoiceProcessingEnabled(true)
                Logger.debug("[SoundPlayer] Voice processing enabled for \(config.playbackMode) mode")
            } else {
                Logger.debug("[SoundPlayer] Voice processing disabled for regular mode")
            }
        }
        self.isAudioEngineIsSetup = true
        
        try self.audioEngine.start()
    }
    
    /// Clears all pending audio chunks from the playback queue
    /// - Parameter promise: Promise to resolve when queue is cleared
    func clearSoundQueue(turnIdToClear turnId: String = "", resolver promise: Promise) {
        Logger.debug("[SoundPlayer] Clearing Sound Queue...")
        if !self.audioQueue.isEmpty {
            Logger.debug("[SoundPlayer] Queue is not empty clearing")
            self.audioQueue.removeAll(where: { $0.turnId == turnId } )
        } else {
            Logger.debug("[SoundPlayer] Queue is empty")
        }
        promise.resolve(nil)
    }
    
    /// Stops audio playback and clears the queue
    /// - Parameter promise: Promise to resolve when stopped
    func stop(_ promise: Promise) {
        Logger.debug("[SoundPlayer] Stopping Audio")
        if !self.audioQueue.isEmpty {
            Logger.debug("[SoundPlayer] Queue is not empty clearing")
            self.audioQueue.removeAll()
        }
          // Stop the audio player node
        if self.audioPlayerNode != nil && self.audioPlayerNode.isPlaying {
            Logger.debug("[SoundPlayer] Player is playing stopping")
            self.audioPlayerNode.pause()
            self.audioPlayerNode.stop()
        } else {
            Logger.debug("Player is not playing")
        }
        self.segmentsLeftToPlay = 0
        promise.resolve(nil)
    }
    
    /// Interrupts audio playback
    /// - Parameter promise: Promise to resolve when interrupted
    func interrupt(_ promise: Promise) {
        self.isInterrupted = true
        self.stop(promise)
    }
    
    /// Resumes audio playback after interruption
    func resume() {
        self.isInterrupted = false
    }
    
    /// Plays a WAV audio file from base64 encoded data
    /// - Parameter base64String: Base64 encoded WAV audio data
    /// - Note: This method plays the audio directly without queueing, using AVAudioPlayer
    /// - Important: The base64 string must represent valid WAV format audio data
    public func playWav(base64Wav base64String: String) {
        guard let data = Data(base64Encoded: base64String) else {
            Logger.debug("[SoundPlayer] Invalid Base64 String [ \(base64String)]")
            return
        }
        do {
            self.audioPlayer = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            self.audioPlayer!.volume = 1.0
            audioPlayer!.play()
        } catch {
            Logger.debug("[SoundPlayer] Error playing WAV audio [ \(error)]")
        }
    }
    
    /// Processes audio chunk based on common format
    /// - Parameters:
    ///   - base64String: Base64 encoded audio data
    ///   - commonFormat: The common format of the audio data
    /// - Returns: Processed audio buffer or nil if processing fails
    /// - Throws: SoundPlayerError if format is unsupported
    private func processAudioChunk(_ base64String: String, commonFormat: AVAudioCommonFormat) throws -> AVAudioPCMBuffer? {
        switch commonFormat {
        case .pcmFormatFloat32:
            return AudioUtils.processFloat32LEAudioChunk(base64String, audioFormat: self.audioPlaybackFormat)
        case .pcmFormatInt16:
            return AudioUtils.processPCM16LEAudioChunk(base64String, audioFormat: self.audioPlaybackFormat)
        default:
            Logger.debug("[SoundPlayer] Unsupported audio format: \(commonFormat)")
            throw SoundPlayerError.unsupportedFormat
        }
    }
    
    /// Plays an audio chunk from base64 encoded string
    /// - Parameters:
    ///   - base64String: Base64 encoded audio data
    ///   - strTurnId: Identifier for the turn/segment
    ///   - resolver: Promise resolver callback
    ///   - rejecter: Promise rejection callback
    ///   - commonFormat: The common format of the audio data (defaults to .pcmFormatFloat32)
    /// - Throws: Error if audio processing fails
    public func play(
        audioChunk base64String: String,
        turnId strTurnId: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock,
        commonFormat: AVAudioCommonFormat = .pcmFormatFloat32
    ) throws {
        Logger.debug("New play chunk \(self.isInterrupted)")
        guard !self.isInterrupted else {
            resolver(nil)
            return
        }
        
        do {
            if !self.isAudioEngineIsSetup {
                try ensureAudioEngineIsSetup()
            }
            
            guard let buffer = try processAudioChunk(base64String, commonFormat: commonFormat) else {
                Logger.debug("[SoundPlayer] Failed to process audio chunk")
                throw SoundPlayerError.invalidBase64String
            }
                        
            let bufferTuple = (buffer: buffer, promise: resolver, turnId: strTurnId)
            audioQueue.append(bufferTuple)
            if self.segmentsLeftToPlay == 0 && strTurnId != suspendSoundEventTurnId {
                self.delegate?.onSoundStartedPlaying()
            }
            self.segmentsLeftToPlay += 1
            // If not already playing, start playback
            if audioQueue.count == 1 {
                Logger.debug("[SoundPlayer] Starting playback [ \(audioQueue.count)]")
                playNextInQueue()
            }
        } catch {
            Logger.debug("[SoundPlayer] Failed to enqueue audio chunk: \(error.localizedDescription)")
            rejecter("ERROR_SOUND_PLAYER", "Failed to enqueue audio chunk: \(error.localizedDescription)", nil)
        }
    }
    
    /// Plays the next audio buffer in the queue
    /// This method is responsible for:
    /// 1. Checking if there are audio chunks in the queue
    /// 2. Starting the audio player node if it's not already playing
    /// 3. Scheduling the next audio buffer for playback
    /// 4. Handling completion callbacks and recursively playing the next chunk
    private func playNextInQueue() {
        // Exit if there are no audio chunks in the queue
        guard !audioQueue.isEmpty else {
            return
        }
                
        Logger.debug("[SoundPlayer] Playing audio [ \(audioQueue.count)]")
          
        // Start the audio player node if it's not already playing
        if !self.audioPlayerNode.isPlaying {
            Logger.debug("[SoundPlayer] Starting Player")
            self.audioPlayerNode.play()
        }
        
        // Use a dedicated queue for buffer access to avoid blocking the main thread
        self.bufferAccessQueue.async {
            // Get the first buffer tuple from the queue (buffer, promise, turnId)
            if let (buffer, promise, turnId) = self.audioQueue.first {
                // Remove the buffer from the queue immediately to avoid playing it twice
                self.audioQueue.removeFirst()

                // Schedule the buffer for playback with a completion handler
                self.audioPlayerNode.scheduleBuffer(buffer) {
                    // Decrement the count of segments left to play
                    self.segmentsLeftToPlay -= 1
                    // Check if this is the final segment in the current sequence
                    let isFinalSegment = self.segmentsLeftToPlay == 0
                    
                    // Notify delegate about playback completion (unless using the suspend events ID)
                    if turnId != self.suspendSoundEventTurnId {
                        self.delegate?.onSoundChunkPlayed(isFinalSegment)
                    }
                    // Resolve the promise to indicate successful playback
                    promise(nil)
                    
                    // If this is the final segment and we're in voiceProcessing mode,
                    // stop the audio engine to clean up resources
                    if isFinalSegment && self.config.playbackMode == .voiceProcessing {
                        Logger.debug("[SoundPlayer] Final segment in voice processing mode, stopping engine")
                        if let engine = self.audioEngine, engine.isRunning {
                            engine.stop()
                            self.isAudioEngineIsSetup = false
                        }
                    }
                    
                    // Recursively play the next chunk if not interrupted and queue is not empty
                    if !self.isInterrupted && !self.audioQueue.isEmpty {
                        self.playNextInQueue()
                    }
                }
            }
        }
    }
}

