import AVFoundation
import ExpoModulesCore
//  RealTimeAudioManager.swift
//  Pods
//
//  Created by Alexander Demchuk on 15/12/2024.
//

public enum SoundPlayerError: Error {
    case invalidBase64String
    case couldNotPlayAudio
    case decodeError(details: String)
}

class Microphone {
    weak var delegate: MicrophoneDataDelegate?
    
    private var audioEngine: AVAudioEngine!
    private var audioConverter: AVAudioConverter!
    private var inputNode: AVAudioInputNode!
    private var audioPlayerNode: AVAudioPlayerNode = AVAudioPlayerNode()
    
    private var isMuted = false
    private var isVoiceProcessingEnabled: Bool = false
    
    
    internal var lastEmissionTime: Date?
    internal var lastEmittedSize: Int64 = 0
    private var emissionInterval: TimeInterval = 1.0 // Default to 1 second
    private var totalDataSize: Int64 = 0
    private var isPaused = false
    private var pausedDuration = 0
    private var fileManager = FileManager.default
    internal var recordingSettings: RecordingSettings?
    internal var recordingUUID: UUID?
    internal var mimeType: String = "audio/wav"
    private var lastBufferTime: AVAudioTime?
    private var accumulatedData = Data()
    private var accumulatedData16kHz = Data()
    private var recentData = [Float]() // This property stores the recent audio data
    
    internal var recordingFileURL: URL?
    private var startTime: Date?
    private var pauseStartTime: Date?
    

    private var inittedAudioSession = false
    private var isRecording: Bool = false
    
    public static let sampleRate: Double = 44100
    public static let isLinear16PCM: Bool = true
    // Linear16 PCM is a standard format well-supported by EVI (although you must send
    // a `session_settings` message to inform EVI of the sample rate). Because there is
    // a wide variance of the native format/ sample rate from input devices, we use the
    // AVAudioConverter API to convert the audio to this standard format in order to
    // remove all guesswork.
    private static let desiredInputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: false)!
    private let audioPlaybackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)
    
    init() {
        if #available(iOS 15.0, *) {
            AVCaptureDevice.showSystemUserInterface(.microphoneModes)
        } else {
            // Fallback on earlier versions
        }
    }

    private func setupVoiceProcessing() {
        self.isMuted = false
        self.isVoiceProcessingEnabled = true
        audioEngine = AVAudioEngine()
        
        do {
            let outputNode: AVAudioOutputNode = audioEngine.outputNode
            self.inputNode = audioEngine.inputNode
            let mainMixerNode: AVAudioMixerNode = audioEngine.mainMixerNode
            audioEngine.connect(mainMixerNode, to: outputNode, format: nil)
            
            // This step, importantly, tells iOS to enable "voice processing" i.e. noise reduction / echo cancellation
            // to optimize the audio input for voice processing. Note that this is simply a
            // *request* to the operating system to enable these features, and there is no guarantee
            // that they will be supported in all environments.
            // Notably, echo cancellation doesn't seem to work in the iOS simulator.
            try self.inputNode.setVoiceProcessingEnabled(true)
            //try outputNode.setVoiceProcessingEnabled(true)
        } catch {
            print("Error setting voice processing: \(error)")
            return
        }
    }
    
    private func ensureInittedAudioSession() throws {
         if self.inittedAudioSession { return }
         let audioSession = AVAudioSession.sharedInstance()
         try audioSession.setCategory(
             .playAndRecord, mode: .voiceChat,
             options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
         try audioSession.setActive(true)
         inittedAudioSession = true
     }
    
    public func startRecording() throws {
        guard !self.isRecording else { return }
        if !self.inittedAudioSession {
            try ensureInittedAudioSession()
        }
        if !self.isVoiceProcessingEnabled {
            setupVoiceProcessing()
        }
        let nativeInputFormat = self.inputNode.inputFormat(forBus: 0)
        // The sample rate is "samples per second", so multiplying by 0.1 should get us chunks of about 100ms
        let inputBufferSize = UInt32(nativeInputFormat.sampleRate * 0.1)
        self.inputNode.installTap(onBus: 0, bufferSize: inputBufferSize, format: nativeInputFormat) { (buffer, time) in
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: Microphone.desiredInputFormat, frameCapacity: 1024)!
           
           var error: NSError? = nil

            let silence = Data(repeating: 0, count: Int(convertedBuffer.frameCapacity) * Int(convertedBuffer.format.streamDescription.pointee.mBytesPerFrame))
           if self.isMuted {
               // The standard behavior for muting is to send audio frames filled with empty data
               // (versus not sending anything during mute). This helps audio systems distinguish
               // between muted-but-still-active streams and streams that have become disconnected.
               
               self.delegate?.onMicrophoneData(silence, silence)
               return
           }
            let inputAudioConverter = AVAudioConverter(from: nativeInputFormat, to: Microphone.desiredInputFormat)!
           let status = inputAudioConverter.convert(to: convertedBuffer, error: &error, withInputFrom: {inNumPackets, outStatus in
               outStatus.pointee = .haveData
               buffer.frameLength = inNumPackets
               return buffer
           })
           
           if status == .haveData {
               let byteLength = Int(convertedBuffer.frameLength) * Int(convertedBuffer.format.streamDescription.pointee.mBytesPerFrame)
               let audioData = Data(bytes: convertedBuffer.audioBufferList.pointee.mBuffers.mData!, count: byteLength)
               self.delegate?.onMicrophoneData(audioData, silence)
               return
           }
           if error != nil {
               print("Error during audio conversion: \(error!.localizedDescription)")
               return
           }
           print( "Unexpected status during audio conversion: \(status)")
       }
       
       if (!audioEngine.isRunning) {
           try audioEngine.start()
       }
        self.isRecording = true
    }
    
    
    func startRecording(settings: RecordingSettings, intervalMilliseconds: Int) -> StartRecordingResult? {
        if !self.isVoiceProcessingEnabled {
            setupVoiceProcessing()
        }
        guard !isRecording else {
            Logger.debug("Debug: Recording is already in progress.")
            return StartRecordingResult(error: "Recording is already in progress.")
        }
        
        if audioEngine.isRunning  {
            Logger.debug("Debug: Audio engine already running.")
            audioEngine.stop()
        }
        
        var newSettings = settings  // Make settings mutable
        
        // Determine the commonFormat based on bitDepth
        let commonFormat: AVAudioCommonFormat
        switch newSettings.bitDepth {
        case 16:
            commonFormat = .pcmFormatInt16
        case 32:
            commonFormat = .pcmFormatInt32
        default:
            Logger.debug("Unsupported bit depth. Defaulting to 16-bit PCM")
            commonFormat = .pcmFormatInt16
            newSettings.bitDepth = 16
        }
        
        emissionInterval = max(100.0, Double(intervalMilliseconds)) / 1000.0
        lastEmissionTime = Date()
        accumulatedData.removeAll()
        totalDataSize = 0
        pausedDuration = 0
        isPaused = false
        
        do {
            let session = AVAudioSession.sharedInstance()
            Logger.debug("Debug: Configuring audio session with sample rate: \(settings.sampleRate) Hz")
            
            // Check if the input node supports the desired format
            let inputNode = audioEngine.inputNode
            let hardwareFormat = inputNode.inputFormat(forBus: 0)
            if hardwareFormat.sampleRate != newSettings.sampleRate {
                Logger.debug("Debug: Preferred sample rate not supported. Falling back to hardware sample rate \(session.sampleRate).")
                newSettings.sampleRate = session.sampleRate
            }
            
            try session.setPreferredSampleRate(settings.sampleRate)
            try session.setPreferredIOBufferDuration(1024 / settings.sampleRate)
            try session.setActive(true)
            
            let actualSampleRate = session.sampleRate
            if actualSampleRate != newSettings.sampleRate {
                Logger.debug("Debug: Preferred sample rate not set. Falling back to hardware sample rate: \(actualSampleRate) Hz")
                newSettings.sampleRate = actualSampleRate
            }
            Logger.debug("Debug: Audio session is successfully configured. Actual sample rate is \(actualSampleRate) Hz")
            
            recordingSettings = newSettings  // Update the class property with the new settings
        } catch {
            Logger.debug("Error: Failed to set up audio session with preferred settings: \(error.localizedDescription)")
            return StartRecordingResult(error: "Error: Failed to set up audio session with preferred settings: \(error.localizedDescription)")
        }
        
        // Correct the format to use 16-bit integer (PCM)
        guard let audioFormat = AVAudioFormat(commonFormat: commonFormat, sampleRate: newSettings.sampleRate, channels: UInt32(newSettings.numberOfChannels), interleaved: true) else {
            Logger.debug("Error: Failed to create audio format with the specified bit depth.")
            return StartRecordingResult(error: "Error: Failed to create audio format with the specified bit depth.")
        }
        
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { [weak self] (buffer, time) in
            guard let self = self else {
                Logger.debug("Error: File URL or self is nil during buffer processing.")
                return
            }
            
            // Processing the current buffer
            self.processAudioBuffer(buffer)
            self.lastBufferTime = time
        }
        
        do {
            startTime = Date()
            try audioEngine.start()
            isRecording = true
            Logger.debug("Debug: Recording started successfully.")
            return StartRecordingResult(
                fileUri: "",
                mimeType: mimeType,
                channels: settings.numberOfChannels,
                bitDepth: settings.bitDepth,
                sampleRate: settings.sampleRate
            )
        } catch {
            Logger.debug("Error: Could not start the audio engine: \(error.localizedDescription)")
            isRecording = false
            return StartRecordingResult(error: "Error: Could not start the audio engine: \(error.localizedDescription)")
        }
    }
    
    public func stopRecording() {
        guard self.isRecording else { return }
        self.isRecording = false
        self.isVoiceProcessingEnabled = false
        audioEngine.stop()
        self.inputNode.removeTap(onBus: 0)
    }

    
    /// Resamples the audio buffer using vDSP. If it fails, falls back to manual resampling.
    /// - Parameters:
    ///   - buffer: The original audio buffer to be resampled.
    ///   - originalSampleRate: The sample rate of the original audio buffer.
    ///   - targetSampleRate: The desired sample rate to resample to.
    /// - Returns: A new audio buffer resampled to the target sample rate, or nil if resampling fails.
    private func resampleAudioBuffer(_ buffer: AVAudioPCMBuffer, from originalSampleRate: Double, to targetSampleRate: Double) -> AVAudioPCMBuffer? {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let sourceFrameCount = Int(buffer.frameLength)
        let sourceChannels = Int(buffer.format.channelCount)
        
        // Calculate the number of frames in the target buffer
        let targetFrameCount = Int(Double(sourceFrameCount) * targetSampleRate / originalSampleRate)
        
        // Create a new audio buffer for the resampled data
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(targetFrameCount)) else { return nil }
        targetBuffer.frameLength = AVAudioFrameCount(targetFrameCount)
        
        let resamplingFactor = Float(targetSampleRate / originalSampleRate) // Factor to resample the audio
        
        for channel in 0..<sourceChannels {
            let input = UnsafeBufferPointer(start: channelData[channel], count: sourceFrameCount) // Original channel data
            let output = UnsafeMutableBufferPointer(start: targetBuffer.floatChannelData![channel], count: targetFrameCount) // Buffer for resampled data
            
            var y: [Float] = Array(repeating: 0, count: targetFrameCount) // Temporary array for resampled data
            
            // Resample using vDSP_vgenp which performs interpolation
            vDSP_vgenp(input.baseAddress!, vDSP_Stride(1), [Float](stride(from: 0, to: Float(sourceFrameCount), by: resamplingFactor)), vDSP_Stride(1), &y, vDSP_Stride(1), vDSP_Length(targetFrameCount), vDSP_Length(sourceFrameCount))
            
            for i in 0..<targetFrameCount {
                output[i] = y[i]
            }
        }
        return targetBuffer
    }
    
    
    private func tryConvertToFormat(inputBuffer buffer: AVAudioPCMBuffer, desiredSampleRate sampleRate: Double, desiredChannel channels: AVAudioChannelCount) -> AVAudioPCMBuffer? {
        var error: NSError? = nil
        var commonFormat: AVAudioCommonFormat = .pcmFormatInt16
        switch recordingSettings?.bitDepth {
        case 16:
            commonFormat = .pcmFormatInt16
        case 32:
            commonFormat = .pcmFormatInt32
        default:
            Logger.debug("Unsupported bit depth. Defaulting to 16-bit PCM")
            commonFormat = .pcmFormatInt16
        }
        guard let nativeInputFormat = AVAudioFormat(commonFormat: commonFormat, sampleRate: buffer.format.sampleRate, channels: 1, interleaved: true) else {
            Logger.debug("AudioSessionManager: Failed to convert to desired format. AudioFormat is corrupted.")
            return nil
        }
        let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: false)!
        let inputAudioConverter = AVAudioConverter(from: nativeInputFormat, to: desiredFormat)!
        
        let convertedBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat, frameCapacity: 1024)!
        let status = inputAudioConverter.convert(to: convertedBuffer, error: &error, withInputFrom: {inNumPackets, outStatus in
           outStatus.pointee = .haveData
           buffer.frameLength = inNumPackets
           return buffer
        })
        if status == .haveData {
            return convertedBuffer
        }
        return nil
    }
    
    
    
    /// Processes the audio buffer and writes data to the file. Also handles audio processing if enabled.
    /// - Parameters:
    ///   - buffer: The audio buffer to process.
    ///   - fileURL: The URL of the file to write the data to.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let targetSampleRate = recordingSettings?.desiredSampleRate ?? buffer.format.sampleRate
        let finalBuffer: AVAudioPCMBuffer
        
        if buffer.format.sampleRate != targetSampleRate {
            // Resample the audio buffer if the target sample rate is different from the input sample rate
            if let resampledBuffer = resampleAudioBuffer(buffer, from: buffer.format.sampleRate, to: targetSampleRate) {
                finalBuffer = resampledBuffer
            } else {
                Logger.debug("Fallback to AVAudioConverter. Converting from \(buffer.format.sampleRate) Hz to \(targetSampleRate) Hz")
                
                if let convertedBuffer = self.tryConvertToFormat(inputBuffer: buffer, desiredSampleRate: targetSampleRate, desiredChannel: 1) {
                    finalBuffer = convertedBuffer
                } else {
                    Logger.debug("Failed to convert to desired format.")
                    finalBuffer = buffer
                }
            }
        } else {
            // Use the original buffer if the sample rates are the same
            finalBuffer = buffer
        }
        
        
        
        let audioData = finalBuffer.audioBufferList.pointee.mBuffers
        guard let bufferData = audioData.mData else {
            Logger.debug("Buffer data is nil.")
            return
        }
        var data = Data(bytes: bufferData, count: Int(audioData.mDataByteSize))
        
        // Accumulate new data
        accumulatedData.append(data)
        
        let pmcBuffer16kHz = self.tryConvertToFormat(inputBuffer: buffer, desiredSampleRate: 16000, desiredChannel: 1)!
        let audioData16kHz = pmcBuffer16kHz.audioBufferList.pointee.mBuffers
        guard let bufferData16kHz = audioData16kHz.mData else {
            Logger.debug("Buffer data is nil.")
            return
        }
        
        var data16kHz = Data(bytes: bufferData16kHz, count: Int(audioData16kHz.mDataByteSize))
        accumulatedData16kHz.append(data16kHz)
        
        
        totalDataSize += Int64(data.count)
        //        print("Total data size written: \(totalDataSize) bytes")  // Debug: Check total data written
        
        let currentTime = Date()
        if let lastEmissionTime = lastEmissionTime, currentTime.timeIntervalSince(lastEmissionTime) >= emissionInterval {
            if let startTime = startTime {
                let recordingTime = currentTime.timeIntervalSince(startTime)
                // Copy accumulated data for processing
                let dataToProcess = accumulatedData
                let dataToProcess16kHz = accumulatedData16kHz
                
                // Emit the processed audio data
                self.delegate?.onMicrophoneData(dataToProcess, dataToProcess16kHz)
                
                self.lastEmissionTime = currentTime // Update last emission time
                self.lastEmittedSize = totalDataSize
                accumulatedData.removeAll() // Reset accumulated data after emission
                accumulatedData16kHz.removeAll()
            }
        }
    }
}
