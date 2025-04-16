package expo.modules.audiostream

import android.media.AudioRecord
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.util.Log

/**
 * Manages audio effects for voice recording, including:
 * - Acoustic Echo Cancellation (AEC)
 * - Noise Suppression (NS)
 * - Automatic Gain Control (AGC)
 */
class AudioEffectsManager {
    // Audio effects
    private var acousticEchoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var automaticGainControl: AutomaticGainControl? = null

    /**
     * Sets up audio effects for the provided AudioRecord instance
     * @param audioRecord The AudioRecord instance to apply effects to
     */
    fun setupAudioEffects(audioRecord: AudioRecord) {
        val audioSessionId = audioRecord.audioSessionId
        
        // Release any existing effects first
        releaseAudioEffects()
        
        try {
            // Log availability of audio effects
            Log.d(Constants.TAG, "AEC available: ${AcousticEchoCanceler.isAvailable()}")
            Log.d(Constants.TAG, "NS available: ${NoiseSuppressor.isAvailable()}")
            Log.d(Constants.TAG, "AGC available: ${AutomaticGainControl.isAvailable()}")
            
            // Apply echo cancellation if available
            if (AcousticEchoCanceler.isAvailable()) {
                acousticEchoCanceler = AcousticEchoCanceler.create(audioSessionId)
                acousticEchoCanceler?.enabled = true
                Log.d(Constants.TAG, "Acoustic Echo Canceler enabled: ${acousticEchoCanceler?.enabled}")
            }
            
            // Apply noise suppression
            enableNoiseSuppression(audioSessionId)
            
            // Apply automatic gain control
            enableAutomaticGainControl(audioSessionId)
            
        } catch (e: Exception) {
            Log.e(Constants.TAG, "Error setting up audio effects", e)
        }
    }

    /**
     * Enables Noise Suppression if available for the given audio session.
     * @param audioSessionId The audio session ID to apply the effect to.
     */
    private fun enableNoiseSuppression(audioSessionId: Int) {
        // Apply noise suppression if available
        if (NoiseSuppressor.isAvailable()) {
            noiseSuppressor = NoiseSuppressor.create(audioSessionId)
            noiseSuppressor?.enabled = true
            Log.d(Constants.TAG, "Noise Suppressor enabled: ${noiseSuppressor?.enabled}")
        }
    }

    /**
     * Enables Automatic Gain Control if available for the given audio session.
     * @param audioSessionId The audio session ID to apply the effect to.
     */
    private fun enableAutomaticGainControl(audioSessionId: Int) {
        // Apply automatic gain control if available
        if (AutomaticGainControl.isAvailable()) {
            automaticGainControl = AutomaticGainControl.create(audioSessionId)
            automaticGainControl?.enabled = true
            Log.d(Constants.TAG, "Automatic Gain Control enabled: ${automaticGainControl?.enabled}")
        }
    }

    /**
     * Releases all audio effects
     */
    fun releaseAudioEffects() {
        try {
            acousticEchoCanceler?.let {
                if (it.enabled) it.enabled = false
                it.release()
                acousticEchoCanceler = null
            }
            
            noiseSuppressor?.let {
                if (it.enabled) it.enabled = false
                it.release()
                noiseSuppressor = null
            }
            
            automaticGainControl?.let {
                if (it.enabled) it.enabled = false
                it.release()
                automaticGainControl = null
            }
        } catch (e: Exception) {
            Log.e(Constants.TAG, "Error releasing audio effects", e)
        }
    }
} 