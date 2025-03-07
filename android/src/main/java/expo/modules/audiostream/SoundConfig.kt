package expo.modules.audiostream

/**
 * Defines different playback modes for audio processing
 */
enum class PlaybackMode {
    /**
     * Regular playback mode for standard audio playback
     */
    REGULAR,
    
    /**
     * Conversation mode optimized for speech
     */
    CONVERSATION,
    
    /**
     * Voice processing mode with enhanced voice quality
     */
    VOICE_PROCESSING
}

/**
 * Configuration for audio playback settings
 */
data class SoundConfig(
    /**
     * The sample rate for audio playback in Hz
     */
    val sampleRate: Int = 44100,
    
    /**
     * The playback mode (regular, conversation, or voiceProcessing)
     */
    val playbackMode: PlaybackMode = PlaybackMode.REGULAR
) {
    companion object {
        /**
         * Default configuration with standard settings
         */
        val DEFAULT = SoundConfig(
            sampleRate = 44100,
            playbackMode = PlaybackMode.REGULAR
        )
    }
} 