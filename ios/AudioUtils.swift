import AVFoundation
import ExpoModulesCore

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
}
