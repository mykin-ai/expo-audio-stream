import AVFoundation

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
        let result = int16Samples.withUnsafeMutableBytes { buffer in
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
}
