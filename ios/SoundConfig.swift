/// Defines different playback modes for audio processing
public enum PlaybackMode {
    /// Regular playback mode for standard audio playback
    case regular
    
    /// Conversation mode optimized for speech
    case conversation
    
    /// Voice processing mode with enhanced voice quality and automatic engine cleanup
    case voiceProcessing
}

/// Configuration for audio playback settings
public struct SoundConfig {
    /// The sample rate for audio playback in Hz
    public var sampleRate: Double
    
    /// The playback mode (regular, conversation, or voiceProcessing)
    public var playbackMode: PlaybackMode
    
    /// Default configuration with standard settings
    public static let defaultConfig = SoundConfig(
        sampleRate: 44100.0,
        playbackMode: .regular
    )
    
    /// Creates a new sound configuration with the specified settings
    /// - Parameters:
    ///   - sampleRate: The sample rate in Hz (default: 44100.0)
    ///   - playbackMode: The playback mode (default: .regular)
    public init(
        sampleRate: Double = 44100.0,
        playbackMode: PlaybackMode = .regular
    ) {
        self.sampleRate = sampleRate
        self.playbackMode = playbackMode
    }
    
    /// Resets the configuration to default values
    /// - Returns: The updated configuration with default values
    public mutating func resetToDefault() -> SoundConfig {
        self = SoundConfig.defaultConfig
        return self
    }
}
