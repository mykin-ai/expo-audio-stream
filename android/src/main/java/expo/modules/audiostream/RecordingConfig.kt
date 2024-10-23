package expo.modules.audiostream

data class RecordingConfig(
    val sampleRate: Int = Constants.DEFAULT_SAMPLE_RATE,
    val channels: Int = 1,
    val encoding: String = "pcm_16bit",
    val interval: Long = Constants.DEFAULT_INTERVAL,
    val pointsPerSecond: Double = 20.0
)

