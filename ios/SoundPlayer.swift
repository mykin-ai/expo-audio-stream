import AVFoundation
import ExpoModulesCore

class SoundPlayer {
    weak var delegate: SoundPlayerDelegate?
    private var audioEngine: AVAudioEngine!

    private var inputNode: AVAudioInputNode!
    private var audioPlayerNode: AVAudioPlayerNode!
    
    private var audioPlayer: AVAudioPlayer?
    
    private var isVoiceProcessingEnabled: Bool = false
    
    private let bufferAccessQueue = DispatchQueue(label: "com.expoaudiostream.bufferAccessQueue")
    
    private var audioQueue: [(buffer: AVAudioPCMBuffer, promise: RCTPromiseResolveBlock, turnId: String)] = []  // Queue for audio segments
    // needed to track segments in progress in order to send playbackevents properly
    private var segmentsLeftToPlay: Int = 0
    private var isPlaying: Bool = false  // Tracks if audio is currently playing
    private var isInterrupted: Bool = false
    private var isAudioEngineIsSetup: Bool = false
  
    private let audioPlaybackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)
    
    init() {
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
            if let audioEngine = self.audioEngine {
                if audioEngine.isRunning {
                    audioEngine.stop()
                }
                self.detachOldAvNodesFromEngine()
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
    
    /// Sets up the audio engine and player node if not already configured
    /// - Throws: Error if audio engine setup fails
    private func ensureAudioEngineIsSetup() throws {
        self.audioEngine = AVAudioEngine()
                    
        audioPlayerNode = AVAudioPlayerNode()
        if let playerNode = self.audioPlayerNode {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: self.audioPlaybackFormat)
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
            
            self.segmentsLeftToPlay = 0
            
            self.isPlaying = false
        } else {
            Logger.debug("Player is not playing")
        }
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
    
    /// Plays an audio chunk from base64 encoded string
    /// - Parameters:
    ///   - base64String: Base64 encoded audio data
    ///   - strTurnId: Identifier for the turn/segment
    ///   - resolver: Promise resolver callback
    ///   - rejecter: Promise rejection callback
    /// - Throws: Error if audio processing fails
    public func play(
        audioChunk base64String: String,
        turnId strTurnId: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
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
            
            guard let data = Data(base64Encoded: base64String) else {
                Logger.debug("[SoundPlayer] Failed to decode base64 string")
                throw SoundPlayerError.invalidBase64String
            }
            guard let pcmData = AudioUtils.removeRIFFHeaderIfNeeded(from: data),
                  let pcmBuffer = AudioUtils.convertPCMDataToBuffer(pcmData, audioFormat: self.audioPlaybackFormat!) else {
                Logger.debug("[SoundPlayer] Failed to process audio chunk")
                return
            }
            let bufferTuple = (buffer: pcmBuffer, promise: resolver, turnId: strTurnId)
            audioQueue.append(bufferTuple)
            self.segmentsLeftToPlay += 1
            print("New Chunk \(isPlaying)")
            // If not already playing, start playback
            playNextInQueue()
        } catch {
            Logger.debug("[SoundPlayer] Failed to enqueue audio chunk: \(error.localizedDescription)")
            rejecter("ERROR_SOUND_PLAYER", "Failed to enqueue audio chunk: \(error.localizedDescription)", nil)
        }
    }
    
    
    private func playNextInQueue() {
        guard !audioQueue.isEmpty else {
            return
        }
        guard !isPlaying else {
            return
        }
        
        Logger.debug("[SoundPlayer] Playing audio [ \(audioQueue.count)]")
          
            
        if !self.audioPlayerNode.isPlaying {
            Logger.debug("[SoundPlayer] Starting Player")
            self.audioPlayerNode.play()
        }
        self.bufferAccessQueue.async {
            if let (buffer, promise, _) = self.audioQueue.first {
                self.audioQueue.removeFirst()

                self.audioPlayerNode.scheduleBuffer(buffer) {
                    self.segmentsLeftToPlay -= 1
                    let isFinalSegment = self.segmentsLeftToPlay == 0
                    
                    self.delegate?.onSoundChunkPlayed(isFinalSegment)
                    promise(nil)
                    

                    if !self.isInterrupted && !self.audioQueue.isEmpty {
                        self.playNextInQueue()
                    }
                }
            }
        }
    }
}

