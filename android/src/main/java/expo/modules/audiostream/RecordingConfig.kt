package expo.modules.audiostream

data class RecordingConfig(
    val sampleRate: Int = Constants.DEFAULT_SAMPLE_RATE,
    val channels: Int = 1,
    val encoding: String = "pcm_16bit",
    val interval: Long = Constants.DEFAULT_INTERVAL,
    val pointsPerSecond: Double = 20.0
) {
    /**
     * Validates the recording configuration
     * @return Error information if invalid, null if valid
     */
    fun validate(): ValidationResult? {
        // Check sample rate
        if (sampleRate !in listOf(16000, 44100, 48000)) {
            return ValidationResult(
                "INVALID_SAMPLE_RATE",
                "Sample rate must be one of 16000, 44100, or 48000 Hz"
            )
        }
        
        // Check channels
        if (channels !in 1..2) {
            return ValidationResult(
                "INVALID_CHANNELS",
                "Channels must be either 1 (Mono) or 2 (Stereo)"
            )
        }
        
        // All checks passed
        return null
    }
    
    companion object {
        /**
         * Creates a RecordingConfig from options map
         * @param options Map containing configuration options
         * @return New RecordingConfig instance
         */
        fun fromOptions(options: Map<String, Any?>): RecordingConfig {
            return RecordingConfig(
                sampleRate = (options["sampleRate"] as? Number)?.toInt() ?: Constants.DEFAULT_SAMPLE_RATE,
                channels = (options["channels"] as? Number)?.toInt() ?: 1,
                encoding = options["encoding"] as? String ?: "pcm_16bit",
                interval = (options["interval"] as? Number)?.toLong() ?: Constants.DEFAULT_INTERVAL,
                pointsPerSecond = (options["pointsPerSecond"] as? Number)?.toDouble() ?: 20.0
            )
        }
    }
}

/**
 * Data class to hold validation error information
 */
data class ValidationResult(
    val code: String,
    val message: String
)

