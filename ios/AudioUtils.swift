import AVFoundation
import ExpoModulesCore

public enum SoundPlayerError: Error {
    case invalidBase64String
    case couldNotPlayAudio
    case decodeError(details: String)
    case unsupportedFormat
}

enum AudioProcessingError: Error {
    case invalidBase64
}

class AudioUtils {
    static func removeRIFFHeaderIfNeeded(from audioData: Data) -> Data? {
        let headerSize = 44 // The "RIFF" header is 44 bytes
        guard audioData.count > headerSize, audioData.starts(with: "RIFF".data(using: .ascii)!) else {
            return audioData
        }
        return audioData.subdata(in: headerSize..<audioData.count)
    }
    
    static func convertPCMDataToBuffer(_ pcmData: Data, audioFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Prepare buffer for Float32 samples
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(pcmData.count / 2)) else {
            print("Failed to create audio buffer.")
            return nil
        }

        var int16Samples = [Int16](repeating: 0, count: pcmData.count / 2)
        let _ = int16Samples.withUnsafeMutableBytes { buffer in
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
    
    /// Resamples the audio buffer using vDSP. If it fails, falls back to manual resampling.
    /// - Parameters:
    ///   - buffer: The original audio buffer to be resampled.
    ///   - originalSampleRate: The sample rate of the original audio buffer.
    ///   - targetSampleRate: The desired sample rate to resample to.
    /// - Returns: A new audio buffer resampled to the target sample rate, or nil if resampling fails.
    static func resampleAudioBuffer(_ buffer: AVAudioPCMBuffer, from originalSampleRate: Double, to targetSampleRate: Double) -> AVAudioPCMBuffer? {
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
    
    static func tryConvertToFormat(
        inputBuffer buffer: AVAudioPCMBuffer,
        desiredSampleRate sampleRate: Double,
        desiredChannel channels: AVAudioChannelCount,
        bitDepth: Int? = nil
    ) -> AVAudioPCMBuffer? {
        var error: NSError? = nil
        let depth = bitDepth ?? 16
        var commonFormat: AVAudioCommonFormat = getCommonFormat(depth: depth)
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
    
    static func getCommonFormat(depth: Int) -> AVAudioCommonFormat {
        var commonFormat: AVAudioCommonFormat = .pcmFormatInt16
        switch depth {
        case 16:
            commonFormat = .pcmFormatInt16
        case 32:
            commonFormat = .pcmFormatInt32
        default:
            Logger.debug("Unsupported bit depth. Defaulting to 16-bit PCM")
            commonFormat = .pcmFormatInt16
        }
        
        return commonFormat
    }
    
    
    static func calculatePowerLevel(from buffer: AVAudioPCMBuffer) -> Float {
        let format = buffer.format.commonFormat
        let length = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var totalRMS: Float = 0.0

        if format == .pcmFormatFloat32, let channelData = buffer.floatChannelData {
            // Process Float32 PCM
            for channel in 0..<channelCount {
                let data = channelData[channel]
                var sum: Float = 0.0
                
                for sample in 0..<length {
                    sum += data[sample] * data[sample]
                }
                
                let channelRMS = sqrt(sum / Float(length))
                totalRMS += channelRMS
            }
        } else if format == .pcmFormatInt16, let channelData = buffer.int16ChannelData {
            // Process Int16 PCM
            for channel in 0..<channelCount {
                let data = channelData[channel]
                var sum: Float = 0.0
                
                for sample in 0..<length {
                    let normalizedSample = Float(data[sample]) / Float(Int16.max) // Convert to -1.0 to 1.0 range
                    sum += normalizedSample * normalizedSample
                }
                
                let channelRMS = sqrt(sum / Float(length))
                totalRMS += channelRMS
            }
        } else {
            return -160.0 // Unsupported format
        }
        
        let avgRMS = totalRMS / Float(channelCount)
        return avgRMS > 0 ? 20 * log10(avgRMS) : -160.0
    }
    
    /// Removes WAV/RIFF header from audio data if present
    /// - Parameter data: The input audio data that might contain a WAV/RIFF header
    /// - Returns: Audio data with WAV/RIFF header removed, or original data if no header found
    static func removeWavHeader(from data: Data) -> Data? {
        // Check if data starts with "RIFF" and is long enough to contain a WAV header
        guard data.count >= 44,
              let riffString = String(data: data.prefix(4), encoding: .ascii),
              riffString == "RIFF",
              let waveString = String(data: data[8..<12], encoding: .ascii),
              waveString == "WAVE" else {
            // If not a WAV file, return original data
            return data
        }
        
        // Find the "data" chunk
        var offset = 12 // Start after RIFF header and WAVE identifier
        while offset < data.count - 8 { // Need at least 8 bytes for chunk header
            let chunkID = String(data: data[offset..<offset+4], encoding: .ascii) ?? ""
            let chunkSize = Int(data[offset+4..<offset+8].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian)
            
            if chunkID == "data" {
                // Found the data chunk, return everything after its header
                let dataStart = offset + 8
                return data.subdata(in: dataStart..<data.count)
            }
            
            // Move to next chunk (chunk header is 8 bytes + chunk size)
            offset += 8 + chunkSize
            // Ensure chunk alignment to 2 bytes
            if chunkSize % 2 != 0 { offset += 1 }
        }
        
        Logger.debug("[AudioUtils] Failed to find data chunk in WAV file")
        return nil
    }
    
    /// Checks if data contains WAV/RIFF header
    /// - Parameter data: The data to check
    /// - Returns: true if data starts with RIFF....WAVE
    static private func isWavFormat(_ data: Data) -> Bool {
        guard data.count >= 12,
              let riffString = String(data: data.prefix(4), encoding: .ascii),
              riffString == "RIFF",
              let waveString = String(data: data[8..<12], encoding: .ascii),
              waveString == "WAVE" else {
            return false
        }
        return true
    }

    /// Processes a raw Float32LE (pcm_f32le) base64 encoded audio chunk and converts it to an AVAudioPCMBuffer
    /// - Parameters:
    ///   - base64String: Base64 encoded raw Float32LE PCM audio data or WAV file (automatically detected)
    ///   - audioFormat: Target audio format for the buffer (should be Float32)
    /// - Returns: AVAudioPCMBuffer containing the processed audio data, or nil if processing fails
    static func processFloat32LEAudioChunk(_ base64String: String, audioFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Verify format is Float32
        guard audioFormat.commonFormat == .pcmFormatFloat32 else {
            Logger.debug("[AudioUtils] Invalid format: expected Float32 format")
            return nil
        }
        
        // Decode base64 string to raw data
        guard let data = Data(base64Encoded: base64String) else {
            Logger.debug("[AudioUtils] Failed to decode base64 string")
            return nil
        }
        
        // Automatically detect and remove WAV header if present
        let audioData: Data
        if isWavFormat(data) {
            Logger.debug("[AudioUtils] WAV format detected, removing header")
            guard let pcmData = removeWavHeader(from: data) else {
                Logger.debug("[AudioUtils] Failed to process WAV header")
                return nil
            }
            audioData = pcmData
        } else {
            Logger.debug("[AudioUtils] Raw PCM format detected")
            audioData = data
        }
        
        // Create buffer for Float32 samples
        let frameCount = AVAudioFrameCount(audioData.count / 4) // 4 bytes per sample for Float32 audio
        let intFrameCount = Int(frameCount)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            Logger.debug("[AudioUtils] Failed to create audio buffer")
            return nil
        }
        
        // Copy float samples directly from data
        pcmBuffer.frameLength = frameCount
        if let channelData = pcmBuffer.floatChannelData {
            audioData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Void in
                guard let addr = bytes.baseAddress else { return }
                let ptr = addr.assumingMemoryBound(to: Float.self)
                for i in 0..<intFrameCount {
                    channelData.pointee[i] = ptr[i]
                }
            }
        }
        
        return pcmBuffer
    }
    
    /// Processes a raw PCM_S16LE (16-bit Little Endian) base64 encoded audio chunk and converts it to an AVAudioPCMBuffer
    /// - Parameters:
    ///   - base64String: Base64 encoded raw PCM_S16LE audio data
    ///   - audioFormat: Target audio format for the buffer (should be Float32)
    /// - Returns: AVAudioPCMBuffer containing the processed audio data, or nil if processing fails
    static func processPCM16LEAudioChunk(_ base64String: String, audioFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Verify format is Float32
        guard audioFormat.commonFormat == .pcmFormatFloat32 else {
            Logger.debug("[AudioUtils] Invalid format: expected Float32 format")
            return nil
        }
        
        // ✅ Add size check to prevent excessive memory allocation
        guard base64String.count < 500_000 else {
            Logger.debug("[AudioUtils] Base64 string too large: \(base64String.count) characters")
            return nil
        }
        
        // ✅ Wrap decoding in autoreleasepool for immediate cleanup
        let data: Data
        do {
            data = try autoreleasepool {
                guard let decodedData = Data(base64Encoded: base64String) else {
                    throw AudioProcessingError.invalidBase64
                }
                return decodedData
            }
        } catch {
            Logger.debug("[AudioUtils] Failed to decode base64 string")
            return nil
        }
        
        // ✅ Validate decoded data size
        guard data.count > 0 && data.count < 2_000_000 else {
            Logger.debug("[AudioUtils] Invalid decoded data size: \(data.count) bytes")
            return nil
        }
        
        // Automatically detect and remove WAV header if present
        let audioData: Data
        if isWavFormat(data) {
            Logger.debug("[AudioUtils] WAV format detected, removing header")
            guard let pcmData = removeWavHeader(from: data) else {
                Logger.debug("[AudioUtils] Failed to process WAV header")
                return nil
            }
            audioData = pcmData
        } else {
            Logger.debug("[AudioUtils] Raw PCM format detected")
            audioData = data
        }
        
        // Create buffer for Float32 samples
        let frameCount = AVAudioFrameCount(audioData.count / 2) // 2 bytes per sample for 16-bit audio
        let intFrameCount = Int(frameCount)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            Logger.debug("[AudioUtils] Failed to create audio buffer")
            return nil
        }
        
        pcmBuffer.frameLength = frameCount
        if let channelData = pcmBuffer.floatChannelData {
            audioData.withUnsafeBytes { ptr in
                guard let addr = ptr.baseAddress else { return }
                let int16ptr = addr.assumingMemoryBound(to: Int16.self)
                for i in 0..<intFrameCount {
                    // Read as little endian Int16 and convert to normalized float (-1.0 to 1.0)
                    let int16Sample = Int16(littleEndian: int16ptr[i])
                    channelData.pointee[i] = Float(int16Sample) / 32768.0
                }
            }
        }
        
        return pcmBuffer
    }
}
