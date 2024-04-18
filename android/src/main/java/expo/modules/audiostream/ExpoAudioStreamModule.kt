package expo.modules.audiostream

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Base64
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.*

class ExpoAudioStreamModule : Module() {
    data class AudioChunk(
        val audioData: FloatArray,
        val promise: Promise,
        var isSettled: Boolean = false
    )

    private val coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var audioTrack: AudioTrack
    private val playbackQueue: ConcurrentLinkedQueue<AudioChunk> = ConcurrentLinkedQueue()
    private var playbackJob: Job? = null

    override fun definition() = ModuleDefinition {
        Name("ExpoAudioStream")

        OnCreate {
            initializeAudioTrack()
            startPlaybackLoop()
        }

        OnDestroy {
            stopPlaybackLoop()
            playbackQueue.clear()
            audioTrack.stop()
            audioTrack.release()
        }

        AsyncFunction("streamRiff16Khz16BitMonoPcmChunk") { chunk: String, promise: Promise ->
            enqueueChunkForPlayback(chunk, promise)
        }

        AsyncFunction("setVolume") { volume: Double, promise: Promise ->
            setVolume(
                volume,
                promise
            )
        }

        AsyncFunction("pause") { promise: Promise -> pausePlayback(promise) }

        AsyncFunction("start") { promise: Promise -> startPlayback(promise) }

        AsyncFunction("stop") { promise: Promise -> stopPlayback(promise) }
    }

    private fun setVolume(volume: Double, promise: Promise) {
        val clampedVolume = max(0.0, min(volume, 100.0)) / 100.0
        try {
            audioTrack.setVolume(clampedVolume.toFloat()) // Set volume method accepts a float value.
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject("ERR_SET_VOLUME", e.toString(), e)
        }
    }

    private fun pausePlayback(promise: Promise) {
        try {
            audioTrack.pause()
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject("ERR_PAUSE_PLAYBACK", e.toString(), e)
        }
    }

    private fun startPlayback(promise: Promise) {
        try {
            if (!audioTrack.playState.equals(AudioTrack.PLAYSTATE_PLAYING)) {
                audioTrack.play()
            }
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject("ERR_START_PLAYBACK", e.toString(), e)
        }
    }

    private fun stopPlayback(promise: Promise) {
        try {
            audioTrack.stop()
            audioTrack.flush() // Clear the buffer by flushing it.
            playbackQueue.clear() // Clear any remaining data in the queue.
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject("ERR_STOP_PLAYBACK", e.toString(), e)
        }
    }

    private fun initializeAudioTrack() {
        val audioFormat =
            AudioFormat.Builder()
                .setSampleRate(16000)
                .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()

        val minBufferSize =
            AudioTrack.getMinBufferSize(
                16000,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_FLOAT
            )

        audioTrack =
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(audioFormat)
                .setBufferSizeInBytes(minBufferSize * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

        // audioTrack.play()
    }

    private fun enqueueChunkForPlayback(chunk: String, promise: Promise) {
        coroutineScope.launch {
            try {
                val decodedBytes = Base64.decode(chunk, Base64.DEFAULT)
                val audioDataWithoutRIFF = removeRIFFHeaderIfNeeded(decodedBytes)
                val audioData = convertPCMDataToFloatArray(audioDataWithoutRIFF)
                playbackQueue.add(AudioChunk(audioData, promise))
            } catch (e: Exception) {
                promise.reject("ERR_PROCESSING_AUDIO", e.toString(), e)
            }
        }
    }

    private fun startPlaybackLoop() {
        coroutineScope.launch {
            while (isActive) { // isActive is now available within CoroutineScope
                if (playbackQueue.isNotEmpty()) {
                    playNextChunk()
                } else {
                    delay(10) // A short delay to prevent busy waiting
                }
            }
        }
    }

    private fun stopPlaybackLoop() {
        playbackJob?.cancel()
        audioTrack.stop()
        audioTrack.flush()
        playbackQueue.forEach {
            if (!it.isSettled) it.promise.reject("ERR_STOPPED", "Playback was stopped", null)
        }
        playbackQueue.clear()
    }

    private suspend fun playNextChunk() {
        val chunk = playbackQueue.poll()
        chunk?.let {
            setupPlaybackCompletionListener(it)
            audioTrack.play()
            audioTrack.write(it.audioData, 0, it.audioData.size, AudioTrack.WRITE_BLOCKING)
        }
    }

    private fun setupPlaybackCompletionListener(chunk: AudioChunk) {
        audioTrack.setPlaybackPositionUpdateListener(null) // Clear previous listener
        audioTrack.setNotificationMarkerPosition(
            chunk.audioData.size
        ) // Set the marker at the end of the current chunk

        audioTrack.setPlaybackPositionUpdateListener(
            object : AudioTrack.OnPlaybackPositionUpdateListener {
                override fun onMarkerReached(track: AudioTrack?) {
                    chunk.promise.resolve(null) // Resolve the promise when playback reaches the marker
                }

                override fun onPeriodicNotification(track: AudioTrack?) {
                    // Not used in this implementation
                }
            }
        )
    }

    private fun convertPCMDataToFloatArray(pcmData: ByteArray): FloatArray {
        val shortBuffer = ByteBuffer.wrap(pcmData).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val shortArray = ShortArray(shortBuffer.remaining())
        shortBuffer.get(shortArray)
        return FloatArray(shortArray.size) { index ->
            shortArray[index] / 32768.0f // Convert to Float32
        }
    }

    private fun removeRIFFHeaderIfNeeded(audioData: ByteArray): ByteArray {
        val headerSize = 44
        val riffHeader = "RIFF".toByteArray(Charsets.US_ASCII)

        // Check if the data is large enough and starts with "RIFF"
        if (audioData.size > headerSize && audioData.startsWith(riffHeader)) {
            return audioData.copyOfRange(headerSize, audioData.size)
        }
        return audioData
    }

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean {
        if (this.size < prefix.size) return false
        for (i in prefix.indices) {
            if (this[i] != prefix[i]) return false
        }
        return true
    }
}
