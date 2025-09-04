import Foundation
import AVFoundation
import ExpoModulesCore

let audioDataEvent: String = "AudioData"
let soundIsPlayedEvent: String = "SoundChunkPlayed"
let soundIsStartedEvent: String = "SoundStarted"
let deviceReconnectedEvent: String = "DeviceReconnected"


public class ExpoPlayAudioStreamModule: Module, AudioStreamManagerDelegate, MicrophoneDataDelegate, SoundPlayerDelegate {
    private var _audioSessionManager: AudioSessionManager?
    private var _microphone: Microphone?
    private var _soundPlayer: SoundPlayer?
    
    private var audioSessionManager: AudioSessionManager {
        if _audioSessionManager == nil {
            _audioSessionManager = AudioSessionManager()
            _audioSessionManager?.delegate = self
        }
        return _audioSessionManager!
    }
    
    private var microphone: Microphone {
        if _microphone == nil {
            _microphone = Microphone()
            _microphone?.delegate = self
        }
        return _microphone!
    }
    
    private var soundPlayer: SoundPlayer {
        if _soundPlayer == nil {
            _soundPlayer = SoundPlayer()
            _soundPlayer?.delegate = self
        }
        return _soundPlayer!
    }
    
    private var isAudioSessionInitialized: Bool = false

    public func definition() -> ModuleDefinition {
        Name("ExpoPlayAudioStream")
        
        // Defines event names that the module can send to JavaScript.
        Events([audioDataEvent, soundIsPlayedEvent, soundIsStartedEvent, deviceReconnectedEvent])
        
        Function("destroy") {
            // Now we can properly reset all instances
            self._audioSessionManager = nil
            self._microphone = nil
            self._soundPlayer = nil
            self.isAudioSessionInitialized = false
        }
        
        /// Prompts the user to select the microphone mode.
        Function("promptMicrophoneModes") {
            promptForMicrophoneModes()
        }
        
        /// Asynchronously starts audio recording with the given settings.
        ///
        /// - Parameters:
        ///   - options: A dictionary containing:
        ///     - `sampleRate`: The sample rate for recording (default is 16000.0).
        ///     - `channelConfig`: The number of channels (default is 1 for mono).
        ///     - `audioFormat`: The bit depth for recording (default is 16 bits).
        ///     - `interval`: The interval in milliseconds at which to emit recording data (default is 1000 ms).
        ///     - `enableProcessing`: Boolean to enable/disable audio processing (default is false).
        ///     - `pointsPerSecond`: The number of data points to extract per second of audio (default is 20).
        ///     - `algorithm`: The algorithm to use for extraction (default is "rms").
        ///     - `featureOptions`: A dictionary of feature options to extract (default is empty).
        ///     - `maxRecentDataDuration`: The maximum duration of recent data to keep for processing (default is 10.0 seconds).
        ///   - promise: A promise to resolve with the recording settings or reject with an error.
        AsyncFunction("startRecording") { (options: [String: Any], promise: Promise) in
            // Extract settings from provided options, using default values if necessary
            let requestedSampleRate = options["sampleRate"] as? Double ?? 48000.0 // Default to 48kHz for iOS
            let numberOfChannels = options["channelConfig"] as? Int ?? 1 // Mono channel configuration
            let bitDepth = options["audioFormat"] as? Int ?? 16 // 16bits
            let interval = options["interval"] as? Int ?? 1000
            
            // Get the actual sample rate that will be used (hardware may override)
            let audioSession = AVAudioSession.sharedInstance()
            let actualSampleRate = audioSession.sampleRate > 0 ? audioSession.sampleRate : requestedSampleRate
            
            Logger.debug("Requested sample rate: \(requestedSampleRate), actual hardware rate: \(actualSampleRate)")
            
            // Create recording settings
            let settings = RecordingSettings(
                sampleRate: actualSampleRate,
                desiredSampleRate: requestedSampleRate,
                numberOfChannels: numberOfChannels,
                bitDepth: bitDepth,
                maxRecentDataDuration: nil,
                pointsPerSecond: nil
            )
            
            if let result = self.audioSessionManager.startRecording(settings: settings, intervalMilliseconds: interval) {
                if let resError = result.error {
                    promise.reject("ERROR", resError)
                } else {
                    let resultDict: [String: Any] = [
                        "fileUri": result.fileUri ?? "",
                        "channels": result.channels ?? 1,
                        "bitDepth": result.bitDepth ?? 16,
                        "sampleRate": result.sampleRate ?? actualSampleRate,
                        "mimeType": result.mimeType ?? "",
                    ]
                    promise.resolve(resultDict)
                }
            } else {
                promise.reject("ERROR", "Failed to start recording.")
            }
        }
        
        /// Pauses audio recording.
        Function("pauseRecording") {
            self.audioSessionManager.pauseRecording()
        }
        
        /// Resumes audio recording.
        Function("resumeRecording") {
            self.audioSessionManager.resumeRecording()
        }
        
        /// Asynchronously stops audio recording and retrieves the recording result.
        ///
        /// - Parameters:
        ///   - promise: A promise to resolve with the recording result or reject with an error.
        AsyncFunction("stopRecording") { (promise: Promise) in
            if let recordingResult = self.audioSessionManager.stopRecording() {
                
                if let resError = recordingResult.error {
                    promise.reject("ERROR", resError)
                } else {
                // Convert RecordingResult to a dictionary
                let resultDict: [String: Any] = [
                    "fileUri": recordingResult.fileUri,
                    "filename": recordingResult.filename ?? "",
                    "durationMs": recordingResult.duration ?? 0,
                    "size": recordingResult.size ?? 0,
                    "channels": recordingResult.channels ?? 1,
                    "bitDepth": recordingResult.bitDepth ?? 16,
                    "sampleRate": recordingResult.sampleRate ?? 48000,
                    "mimeType": recordingResult.mimeType ?? "",
                ]
                promise.resolve(resultDict)}
            } else {
                promise.reject("ERROR", "Failed to stop recording or no recording in progress.")
            }
        }
        
        
        
        AsyncFunction("playAudio") { (base64chunk: String, turnId: String, encoding: String? , promise: Promise) in
            // Determine the audio format based on the encoding parameter
            let commonFormat: AVAudioCommonFormat
            switch encoding {
            case "pcm_f32le":
                commonFormat = .pcmFormatFloat32
            case "pcm_s16le", nil:
                commonFormat = .pcmFormatInt16
            default:
                Logger.debug("[ExpoPlayAudioStreamModule] Unsupported encoding: \(encoding ?? "nil"), defaulting to PCM_S16LE")
                commonFormat = .pcmFormatInt16
            }
            
            audioSessionManager.playAudio(base64chunk, turnId, commonFormat: commonFormat, resolver: { _ in
                promise.resolve(nil)
            }, rejecter: { code, message, error in
                promise.reject(code ?? "ERR_UNKNOWN", message ?? "Unknown error")
            })
        }
        
        AsyncFunction("clearPlaybackQueueByTurnId") { (turnId: String, promise: Promise) in
            audioSessionManager.cleanPlaybackQueue(turnId, resolver: { _ in
                promise.resolve(nil)
            }, rejecter: { code, message, error in
                promise.reject(code ?? "ERR_UNKNOWN", message ?? "Unknown error")
            })
        }

        AsyncFunction("pauseAudio") { (promise: Promise) in
            audioSessionManager.pauseAudio(promise: promise)
        }


        AsyncFunction("stopAudio") { promise in
            audioSessionManager.stopAudio(promise: promise)
        }
        
        AsyncFunction("listAudioFiles") { (promise: Promise) in
            let result = listAudioFiles()
            promise.resolve(result)
        }
        
        AsyncFunction("playSound") { (base64Chunk: String, turnId: String, encoding: String?, promise: Promise) in
            Logger.debug("Play sound")
            do {
                if !isAudioSessionInitialized {
                    try ensureAudioSessionInitialized()
                }
                
                // Determine the audio format based on the encoding parameter
                let commonFormat: AVAudioCommonFormat
                switch encoding {
                case "pcm_f32le":
                    commonFormat = .pcmFormatFloat32
                case "pcm_s16le", nil:
                    commonFormat = .pcmFormatInt16
                default:
                    Logger.debug("[ExpoPlayAudioStreamModule] Unsupported encoding: \(encoding ?? "nil"), defaulting to PCM_S16LE")
                    commonFormat = .pcmFormatInt16
                }
        
                try soundPlayer.play(audioChunk: base64Chunk, turnId: turnId, resolver: {
                    _ in promise.resolve(nil)
                }, rejecter: {code, message, error in
                    promise.reject(code ?? "ERR_UNKNOWN", message ?? "Unknown error")
                }, commonFormat: commonFormat)
            } catch {
                print("Error enqueuing audio: \(error.localizedDescription)")
            }
        }
        
        AsyncFunction("playWav") { (base64Chunk: String, promise: Promise) in
            if !isAudioSessionInitialized {
                do {
                    try ensureAudioSessionInitialized()
                } catch {
                    print("Failed to init audio session \(error.localizedDescription)")
                    return
                }
            }
            soundPlayer.playWav(base64Wav: base64Chunk)
            promise.resolve(nil)
        }
        
        AsyncFunction("stopSound") { (promise: Promise) in
            soundPlayer.stop(promise)
        }
        
        AsyncFunction("interruptSound") { (promise: Promise) in
            soundPlayer.interrupt(promise)
        }
        
        Function("resumeSound") {
            soundPlayer.resume()
        }
        
        AsyncFunction("clearSoundQueueByTurnId") { (turnId: String, promise: Promise) in
            soundPlayer.clearSoundQueue(turnIdToClear: turnId, resolver: promise)
        }
        
        AsyncFunction("startMicrophone") { (options: [String: Any], promise: Promise) in
            // Create recording settings
            // Extract settings from provided options, using default values if necessary
            let sampleRate = options["sampleRate"] as? Double ?? 16000.0 // it fails if not 48000, why?
            let numberOfChannels = options["channelConfig"] as? Int ?? 1 // Mono channel configuration
            let bitDepth = options["audioFormat"] as? Int ?? 16 // 16bits
            let interval = options["interval"] as? Int ?? 1000
            
            let settings = RecordingSettings(
                sampleRate: sampleRate,
                desiredSampleRate: sampleRate,
                numberOfChannels: numberOfChannels,
                bitDepth: bitDepth,
                maxRecentDataDuration: nil,
                pointsPerSecond: nil
            )
            
            if !isAudioSessionInitialized {
                do {
                    try ensureAudioSessionInitialized(settings: settings)
                } catch {
                    promise.reject("ERROR", "Failed to init audio session \(error.localizedDescription)")
                    return
                }
            }            
            
            if let result = self.microphone.startRecording(settings: settings, intervalMilliseconds: interval) {
                if let resError = result.error {
                    promise.reject("ERROR", resError)
                } else {
                    let resultDict: [String: Any] = [
                        "fileUri": result.fileUri ?? "",
                        "channels": result.channels ?? 1,
                        "bitDepth": result.bitDepth ?? 16,
                        "sampleRate": result.sampleRate ?? 48000,
                        "mimeType": result.mimeType ?? "",
                    ]
                    promise.resolve(resultDict)
                }
            } else {
                promise.reject("ERROR", "Failed to start recording.")
            }
        }
        
        /// Stops the microphone recording and releases associated resources
        /// - Parameter promise: A promise to resolve when microphone recording is stopped
        /// - Note: This method stops the active recording session, processes any remaining audio data,
        ///         and releases hardware resources. It should be called when the app no longer needs
        ///         microphone access to conserve battery and system resources.
        AsyncFunction("stopMicrophone") { (promise: Promise) in
            microphone.stopRecording(resolver: promise)
        }
        
        Function("toggleSilence") {
            microphone.toggleSilence()
        }
        
        /// Sets the sound player configuration
        /// - Parameters:
        ///   - config: A dictionary containing configuration options:
        ///     - `sampleRate`: The sample rate for audio playback (default is 16000.0).
        ///     - `playbackMode`: The playback mode ("regular", "voiceProcessing", or "conversation").
        ///     - `useDefault`: When true, resets to default configuration regardless of other parameters.
        ///   - promise: A promise to resolve when configuration is updated or reject with an error.
        AsyncFunction("setSoundConfig") { (config: [String: Any], promise: Promise) in
            // Check if we should use default configuration
            let useDefault = config["useDefault"] as? Bool ?? false
            
            do {
                if !isAudioSessionInitialized {
                    try ensureAudioSessionInitialized()
                }
                
                if useDefault {
                    // Reset to default configuration
                    Logger.debug("[ExpoPlayAudioStreamModule] Resetting sound configuration to default values")
                    try soundPlayer.resetConfigToDefault()
                } else {
                    // Extract configuration values from the provided dictionary
                    let sampleRate = config["sampleRate"] as? Double ?? 16000.0
                    let playbackModeString = config["playbackMode"] as? String ?? "regular"
                    
                    // Convert string playback mode to enum
                    let playbackMode: PlaybackMode
                    switch playbackModeString {
                    case "voiceProcessing":
                        playbackMode = .voiceProcessing
                    case "conversation":
                        playbackMode = .conversation
                    default:
                        playbackMode = .regular
                    }
                    
                    // Create a new SoundConfig object
                    let soundConfig = SoundConfig(sampleRate: sampleRate, playbackMode: playbackMode)
                    
                    // Update the sound player configuration
                    Logger.debug("[ExpoPlayAudioStreamModule] Setting sound configuration - sampleRate: \(sampleRate), playbackMode: \(playbackModeString)")
                    try soundPlayer.updateConfig(soundConfig)
                }
                
                promise.resolve(nil)
            } catch {
                promise.reject("ERROR_CONFIG_UPDATE", "Failed to set sound configuration: \(error.localizedDescription)")
            }
        }
        
        /// Clears all audio files stored in the document directory.
        Function("clearAudioFiles") {
            clearAudioFiles()
        }
    }
    
    private func ensureAudioSessionInitialized(settings recordingSettings: RecordingSettings? = nil) throws {
        if self.isAudioSessionInitialized { return }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord, mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        if let settings = recordingSettings {
            try audioSession.setPreferredSampleRate(settings.sampleRate)
            try audioSession.setPreferredIOBufferDuration(1024 / settings.sampleRate)
        }
        try audioSession.setActive(true)
        isAudioSessionInitialized = true
     }
    
    // used for voice isolation, experimental
    private func promptForMicrophoneModes() {
        guard #available(iOS 15.0, *) else {
            return
        }
        
        if AVCaptureDevice.preferredMicrophoneMode == .voiceIsolation {
            return
        }
        
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }
    
    /// Handles the reception of audio data from the AudioStreamManager.
    ///
    /// - Parameters:
    ///   - manager: The AudioStreamManager instance.
    ///   - data: The received audio data.
    ///   - recordingTime: The current recording time.
    ///   - totalDataSize: The total size of the received audio data.
    func audioStreamManager(_ manager: AudioSessionManager, didReceiveAudioData data: Data, recordingTime: TimeInterval, totalDataSize: Int64) {
        guard let fileURL = manager.recordingFileURL,
              let settings = manager.recordingSettings else { return }
        
        let encodedData = data.base64EncodedString()
        
        // Assuming `lastEmittedSize` and `streamUuid` are tracked within `AudioStreamManager`
        let deltaSize = data.count  // This needs to be calculated based on what was last sent if using chunks
        let fileSize = totalDataSize  // Total data size in bytes
        
        // Calculate the position in milliseconds using the lastEmittedSize
        let sampleRate = settings.sampleRate
        let channels = Double(settings.numberOfChannels)
        let bitDepth = Double(settings.bitDepth)
        let position = Int((Double(manager.lastEmittedSize) / (sampleRate * channels * (bitDepth / 8))) * 1000)
        
        // Construct the event payload similar to Android
        let eventBody: [String: Any] = [
            "fileUri": fileURL.absoluteString,
            "lastEmittedSize": manager.lastEmittedSize,  // Needs to be maintained within AudioStreamManager
            "position": position, // Add position of the chunk in ms since
            "encoded": encodedData,
            "deltaSize": deltaSize,
            "totalSize": fileSize,
            "mimeType": manager.mimeType
        ]
        // Emit the event to JavaScript
        sendEvent(audioDataEvent, eventBody)
    }
    
    /// Checks microphone permission and calls the completion handler with the result.
    ///
    /// - Parameters:
    ///   - completion: A completion handler that receives a boolean indicating whether the microphone permission was granted.
    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }
    
    /// Clears all audio files stored in the document directory.
    private func clearAudioFiles() {
        let fileURLs = listAudioFiles()  // This now returns full URLs as strings
        fileURLs.forEach { fileURLString in
            if let fileURL = URL(string: fileURLString) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    print("Removed file at:", fileURL.path)
                } catch {
                    print("Error removing file at \(fileURL.path):", error.localizedDescription)
                }
            } else {
                print("Invalid URL string: \(fileURLString)")
            }
        }
    }
    
    /// Lists all audio files stored in the document directory.
    ///
    /// - Returns: An array of file URIs as strings.
    func listAudioFiles() -> [String] {
        guard let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else {
            print("Failed to access document directory.")
            return []
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil)
            let audioFiles = files.filter { $0.pathExtension == "wav" }.map { $0.absoluteString }
            return audioFiles
        } catch {
            print("Error listing audio files:", error.localizedDescription)
            return []
        }
    }
    
    func onMicrophoneData(_ microphoneData: Data, _ soundLevel: Float?) {
        let encodedData = microphoneData.base64EncodedString()
        // Construct the event payload similar to Android
        let eventBody: [String: Any] = [
            "fileUri": "",
            "lastEmittedSize": 0,
            "position": 0, // Add position of the chunk in ms since
            "encoded": encodedData,
            "deltaSize": 0,
            "totalSize": 0,
            "mimeType": "",
            "soundLevel": soundLevel ?? -160
        ]
        // Emit the event to JavaScript
        sendEvent(audioDataEvent, eventBody)
    }
    
    func onDeviceReconnected(_ reason: AVAudioSession.RouteChangeReason) {
        let reasonString: String
        switch reason {
        case .newDeviceAvailable:
            reasonString = "newDeviceAvailable"
        case .oldDeviceUnavailable:
            reasonString = "oldDeviceUnavailable"
        case .unknown, .categoryChange, .override, .wakeFromSleep, .noSuitableRouteForCategory, .routeConfigurationChange:
            reasonString = "unknown"
        @unknown default:
            reasonString = "unknown"
        }
        
        sendEvent(deviceReconnectedEvent, ["reason": reasonString])
    }
    
    func onSoundChunkPlayed(_ isFinal: Bool) {
        sendEvent(soundIsPlayedEvent, ["isFinal": isFinal])
    }
    
    func onSoundStartedPlaying() {
        sendEvent(soundIsStartedEvent)
    }
}
