package expo.modules.audiostream

import android.media.MediaDataSource
import android.media.MediaPlayer
import android.util.Base64
import android.util.Log
import expo.modules.kotlin.Promise
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Dedicated player for WAV audio files that handles decoding base64 encoded WAV data
 * and playing it via MediaPlayer.
 */
class WavAudioPlayer {
    private var mediaPlayer: MediaPlayer? = null
    private var isPlaying = false
    private val coroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    /**
     * Plays a WAV file directly using MediaPlayer
     * @param base64Wav Base64 encoded WAV file data
     * @param promise Promise to resolve when playback starts or reject on error
     */
    fun playWavFile(base64Wav: String, promise: Promise) {
        coroutineScope.launch(Dispatchers.IO) {
            try {
                // Release any existing MediaPlayer
                releaseMediaPlayer()
                
                // Decode base64 data
                val decodedBytes = Base64.decode(base64Wav, Base64.DEFAULT)
                
                // Create and prepare MediaPlayer on main thread
                withContext(Dispatchers.Main) {
                    mediaPlayer = MediaPlayer().apply {
                        // Use MediaDataSource directly (no temp file needed)
                        setDataSource(createByteArrayDataSource(decodedBytes))
                        
                        setOnCompletionListener {
                            // Reset playing state using explicit reference to class property
                            this@WavAudioPlayer.isPlaying = false
                        }
                        
                        setOnErrorListener { _, what, extra ->
                            // Reset playing state using explicit reference to class property
                            this@WavAudioPlayer.isPlaying = false
                            Log.e(TAG, "MediaPlayer error: $what, $extra")
                            false
                        }
                        
                        prepare()
                        start()
                        this@WavAudioPlayer.isPlaying = true
                    }
                    
                    // Resolve promise after playback starts
                    promise.resolve(null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error playing WAV file: ${e.message}", e)
                promise.reject("ERR_PLAY_WAV", "Failed to play WAV file: ${e.message}", e)
            }
        }
    }
    
    /**
     * Stops any currently playing WAV file
     * @param promise Promise to resolve when playback is stopped or reject on error
     */
    fun stopWavPlayback(promise: Promise) {
        try {
            mediaPlayer?.apply {
                if (isPlaying) {
                    stop()
                }
                // Make sure we release the media player to clean up resources
                release()
                mediaPlayer = null
                this@WavAudioPlayer.isPlaying = false
            }
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject("ERR_STOP_WAV", "Failed to stop WAV playback: ${e.message}", e)
        }
    }
    
    /**
     * Creates a MediaDataSource from a byte array for direct playback
     */
    private fun createByteArrayDataSource(bytes: ByteArray): MediaDataSource {
        return object : MediaDataSource() {
            override fun close() {
                // Nothing to close
            }
            
            override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
                if (position >= bytes.size) {
                    return -1 // End of data
                }
                
                val remaining = bytes.size - position.toInt()
                val copyLength = minOf(remaining, size)
                System.arraycopy(bytes, position.toInt(), buffer, offset, copyLength)
                return copyLength
            }
            
            override fun getSize(): Long {
                return bytes.size.toLong()
            }
        }
    }
    
    /**
     * Release resources when the player is no longer needed
     */
    fun release() {
        releaseMediaPlayer()
        coroutineScope.cancel()
    }
    
    /**
     * Helper to release the media player resources
     */
    private fun releaseMediaPlayer() {
        mediaPlayer?.apply {
            try {
                if (isPlaying) {
                    stop()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping MediaPlayer: ${e.message}", e)
            }
            release()
        }
        mediaPlayer = null
        isPlaying = false
    }
    
    companion object {
        private const val TAG = "WavAudioPlayer"
    }
} 