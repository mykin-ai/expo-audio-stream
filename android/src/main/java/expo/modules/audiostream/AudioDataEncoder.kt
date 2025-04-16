package expo.modules.audiostream

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.util.Base64
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Data class to hold audio format configuration
 */
data class AudioFormatConfig(
    val audioFormat: Int,
    val fileExtension: String,
    val mimeType: String,
    val error: String? = null
)

class AudioDataEncoder {
    public fun encodeToBase64(rawData: ByteArray): String {
        return Base64.encodeToString(rawData, Base64.NO_WRAP)
    }
    
    /**
     * Calculates the power level (dBFS) of the audio data.
     * Assumes PCM 16-bit encoding.
     *
     * @param audioData The byte array containing audio data.
     * @param bytesRead The number of bytes read into the audioData buffer.
     * @return The power level in dBFS (typically -160.0 to 0.0). Returns -160.0 for silence.
     */
    public fun calculatePowerLevel(audioData: ByteArray, bytesRead: Int): Float {
        if (bytesRead <= 0 || audioData.isEmpty()) {
            return -160.0f // Represent silence or no data
        }

        // Assuming PCM 16-bit, so 2 bytes per sample
        val shorts = ShortArray(bytesRead / 2)
        // Ensure we only process the valid portion of the audioData buffer
        val byteBuffer = ByteBuffer.wrap(audioData, 0, bytesRead).order(ByteOrder.LITTLE_ENDIAN)
        byteBuffer.asShortBuffer().get(shorts)

        if (shorts.isEmpty()) {
             return -160.0f // Represent silence
        }

        var sumOfSquares: Double = 0.0
        for (sample in shorts) {
            val normalizedSample = sample / 32767.0 // Normalize sample to -1.0 to 1.0
            sumOfSquares += normalizedSample * normalizedSample
        }

        val rms = sqrt(sumOfSquares / shorts.size)

        // Handle RMS of 0 (silence) to avoid log10(0)
        if (rms < 1e-9) { // Use a small epsilon to check for effective silence
            return -160.0f
        }

        // Convert RMS to dBFS (dB relative to full scale)
        val dbfs = 20.0 * log10(rms)

        // Clamp the value to a minimum of -160 dBFS, maximum of 0 dBFS
        return dbfs.toFloat().coerceIn(-160.0f, 0.0f)
    }
    
    /**
     * Gets audio format configuration based on the encoding string
     * 
     * @param encoding The encoding string (e.g., "pcm_16bit", "opus", etc.)
     * @return AudioFormatConfig containing audioFormat, fileExtension, and mimeType
     */
    fun getAudioFormatConfig(encoding: String): AudioFormatConfig {
        return when (encoding) {
            "pcm_8bit" -> AudioFormatConfig(
                audioFormat = AudioFormat.ENCODING_PCM_8BIT,
                fileExtension = "wav",
                mimeType = "audio/wav"
            )
            "pcm_16bit" -> AudioFormatConfig(
                audioFormat = AudioFormat.ENCODING_PCM_16BIT,
                fileExtension = "wav",
                mimeType = "audio/wav"
            )
            "pcm_32bit" -> AudioFormatConfig(
                audioFormat = AudioFormat.ENCODING_PCM_FLOAT,
                fileExtension = "wav",
                mimeType = "audio/wav"
            )
            "opus" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    return AudioFormatConfig(
                        audioFormat = AudioFormat.ENCODING_DEFAULT,
                        fileExtension = "wav",
                        mimeType = "audio/wav",
                        error = "Opus encoding not supported on this Android version."
                    )
                }
                AudioFormatConfig(
                    audioFormat = AudioFormat.ENCODING_OPUS,
                    fileExtension = "opus",
                    mimeType = "audio/opus"
                )
            }
            "aac_lc" -> AudioFormatConfig(
                audioFormat = AudioFormat.ENCODING_AAC_LC,
                fileExtension = "aac",
                mimeType = "audio/aac"
            )
            else -> {
                Log.d(Constants.TAG, "Unknown encoding: $encoding, defaulting to PCM_16BIT")
                AudioFormatConfig(
                    audioFormat = AudioFormat.ENCODING_DEFAULT,
                    fileExtension = "wav",
                    mimeType = "audio/wav"
                )
            }
        }
    }
    
    /**
     * Checks if a specific audio format configuration is supported by the device
     * 
     * @param sampleRate The sample rate in Hz
     * @param channels The number of channels (1 for mono, 2 for stereo)
     * @param format The audio format constant from AudioFormat
     * @param permissionUtils The PermissionUtils instance to check recording permissions
     * @return True if the format is supported, false otherwise
     * @throws SecurityException if recording permission is not granted
     */
    fun isAudioFormatSupported(
        sampleRate: Int, 
        channels: Int, 
        format: Int, 
        permissionUtils: PermissionUtils
    ): Boolean {
        if (!permissionUtils.checkRecordingPermission()) {
            throw SecurityException("Recording permission has not been granted")
        }

        val channelConfig = if (channels == 1) AudioFormat.CHANNEL_IN_MONO else AudioFormat.CHANNEL_IN_STEREO
        val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, format)

        if (bufferSize <= 0) {
            return false
        }

        // Always use VOICE_COMMUNICATION for better echo cancellation
        val audioSource = MediaRecorder.AudioSource.VOICE_COMMUNICATION
        
        val audioRecord = AudioRecord(
            audioSource,  // Using VOICE_COMMUNICATION source
            sampleRate,
            channelConfig,
            format,
            bufferSize
        )

        val isSupported = audioRecord.state == AudioRecord.STATE_INITIALIZED
        if (isSupported) {
            val testBuffer = ByteArray(bufferSize)
            audioRecord.startRecording()
            val testRead = audioRecord.read(testBuffer, 0, bufferSize)
            audioRecord.stop()
            if (testRead < 0) {
                return false
            }
        }

        audioRecord.release()
        return isSupported
    }
}