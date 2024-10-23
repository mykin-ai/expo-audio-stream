import Foundation
import AVFoundation
import ExpoModulesCore

let audioDataEvent: String = "AudioData"

public class ExpoPlayAudioStreamModule: Module, AudioStreamManagerDelegate {
    private let audioController = AudioController()
    private let audioSessionManager = AudioSessionManager()

    public func definition() -> ModuleDefinition {
        Name("ExpoPlayAudioStream")
        
        // Defines event names that the module can send to JavaScript.
        Events([audioDataEvent])
        
        OnCreate {
            print("Setting up Audio Session Manager")
            audioSessionManager.delegate = self
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
            self.checkMicrophonePermission { granted in
                guard granted else {
                    promise.reject("PERMISSION_DENIED", "Recording permission has not been granted")
                    return
                }
                
                // Extract settings from provided options, using default values if necessary
                let sampleRate = options["sampleRate"] as? Double ?? 16000.0 // it fails if not 48000, why?
                let numberOfChannels = options["channelConfig"] as? Int ?? 1 // Mono channel configuration
                let bitDepth = options["audioFormat"] as? Int ?? 16 // 16bits
                let interval = options["interval"] as? Int ?? 1000
                
                let pointsPerSecond = options["pointsPerSecond"] as? Int ?? 20
                let maxRecentDataDuration = options["maxRecentDataDuration"] as? Double ?? 10.0
                
                // Create recording settings
                let settings = RecordingSettings(
                    sampleRate: sampleRate,
                    desiredSampleRate: sampleRate,
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
                            "sampleRate": result.sampleRate ?? 48000,
                            "mimeType": result.mimeType ?? "",
                        ]
                        promise.resolve(resultDict)
                    }
                } else {
                    promise.reject("ERROR", "Failed to start recording.")
                }
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
        
        
        
        AsyncFunction("playAudio") { (base64chunk: String, turnId: String, promise: Promise) in
            audioSessionManager.playAudio(base64chunk, turnId, resolver: { _ in
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

        AsyncFunction("setVolume") { (volume: Float, promise: Promise) in
            audioController.setVolume(volume, resolver: { _ in
                promise.resolve(nil)
            }, rejecter: { code, message, error in
                promise.reject(code ?? "ERR_VOLUME_ERROR", message ?? "Error setting volume")
            })
        }

        AsyncFunction("pauseAudio") { (promise: Promise) in
            audioSessionManager.pauseAudio()
            promise.resolve(nil)
        }


        AsyncFunction("stopAudio") { promise in
            audioSessionManager.stopAudio(promise: promise)
        }
        
        AsyncFunction("listAudioFiles") { (promise: Promise) in
            let result = listAudioFiles()
            promise.resolve(result)
        }
        
        /// Clears all audio files stored in the document directory.
        Function("clearAudioFiles") {
            clearAudioFiles()
        }
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
}
