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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

class ExpoAudioStreamModule : Module() {
    data class ChunkData(val chunk: String, val promise: Promise)

    data class AudioChunk(val audioData: FloatArray, val promise: Promise)

    private val coroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private lateinit var audioTrack: AudioTrack
    private val playbackQueue = ConcurrentLinkedQueue<AudioChunk>()
    private val processingChannel = Channel<ChunkData>(Channel.UNLIMITED)
    private var processingJob: Job? = null

    private var isPlaying = false
    private var currentPlaybackJob: Job? = null

    override fun definition() = ModuleDefinition {
        Name("ExpoAudioStream")

        OnCreate { initializeAudioTrack() }

        OnDestroy {
            stopProcessingLoop()
            stopPlayback()
            coroutineScope.cancel()
        }

        AsyncFunction("streamRiff16Khz16BitMonoPcmChunk") { chunk: String, promise: Promise ->
            coroutineScope.launch {
                processingChannel.send(ChunkData(chunk, promise))
                ensureProcessingLoopStarted()
            }
        }

        AsyncFunction("setVolume") { volume: Double, promise: Promise ->
            setVolume(volume, promise)
        }

        AsyncFunction("pause") { promise: Promise -> pausePlayback(promise) }
        AsyncFunction("start") { promise: Promise -> startPlayback(promise) }
        AsyncFunction("stop") { promise: Promise -> stopPlayback(promise) }
    }

    private fun ensureProcessingLoopStarted() {
        if (processingJob == null || processingJob?.isActive != true) {
            startProcessingLoop()
        }
    }

    private fun startProcessingLoop() {
        processingJob =
                coroutineScope.launch {
                    for (chunkData in processingChannel) {
                        processAndEnqueueChunk(chunkData)
                        if (processingChannel.isEmpty && !isPlaying && playbackQueue.isEmpty()) {
                            break // Stop the loop if there's no more work to do
                        }
                    }
                    processingJob = null
                }
    }

    private fun stopProcessingLoop() {
        processingJob?.cancel()
        processingJob = null
    }

    private suspend fun processAndEnqueueChunk(chunkData: ChunkData) {
        try {
            val decodedBytes = Base64.decode(chunkData.chunk, Base64.DEFAULT)
            val audioDataWithoutRIFF = removeRIFFHeaderIfNeeded(decodedBytes)
            val audioData = convertPCMDataToFloatArray(audioDataWithoutRIFF)

            playbackQueue.offer(AudioChunk(audioData, chunkData.promise))

            if (!isPlaying) {
                startPlayback()
            }
        } catch (e: Exception) {
            chunkData.promise.reject("ERR_PROCESSING_AUDIO", e.message, e)
        }
    }

    private fun setVolume(volume: Double, promise: Promise) {
        val clampedVolume = max(0.0, min(volume, 100.0)) / 100.0
        try {
            audioTrack.setVolume(clampedVolume.toFloat())
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject("ERR_SET_VOLUME", e.message, e)
        }
    }

    private fun pausePlayback(promise: Promise? = null) {
        try {
            audioTrack.pause()
            isPlaying = false
            currentPlaybackJob?.cancel()
            promise?.resolve(null)
        } catch (e: Exception) {
            promise?.reject("ERR_PAUSE_PLAYBACK", e.message, e)
        }
    }

    private fun startPlayback(promise: Promise? = null) {
        try {
            if (!isPlaying) {
                audioTrack.play()
                isPlaying = true
                startPlaybackLoop()
            }
            promise?.resolve(null)
        } catch (e: Exception) {
            promise?.reject("ERR_START_PLAYBACK", e.message, e)
        }
    }

    private fun stopPlayback(promise: Promise? = null) {
        try {
            audioTrack.stop()
            audioTrack.flush()
            isPlaying = false
            currentPlaybackJob?.cancel()
            playbackQueue.clear()
            stopProcessingLoop()
            promise?.resolve(null)
        } catch (e: Exception) {
            promise?.reject("ERR_STOP_PLAYBACK", e.message, e)
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
    }

    private fun startPlaybackLoop() {
        currentPlaybackJob =
                coroutineScope.launch {
                    while (isActive && isPlaying) {
                        val chunk = playbackQueue.poll()
                        if (chunk != null) {
                            playChunk(chunk)
                        } else {
                            delay(10)
                        }
                    }
                }
    }

    private suspend fun playChunk(chunk: AudioChunk) {
        withContext(Dispatchers.IO) {
            try {
                val chunkSize = chunk.audioData.size

                suspendCancellableCoroutine { continuation ->
                    val listener =
                            object : AudioTrack.OnPlaybackPositionUpdateListener {
                                override fun onMarkerReached(track: AudioTrack) {
                                    audioTrack.setPlaybackPositionUpdateListener(null)
                                    chunk.promise.resolve(null)
                                    continuation.resumeWith(Result.success(Unit))
                                }

                                override fun onPeriodicNotification(track: AudioTrack) {}
                            }

                    audioTrack.setPlaybackPositionUpdateListener(listener)
                    audioTrack.setNotificationMarkerPosition(chunkSize)
                    val written =
                            audioTrack.write(
                                    chunk.audioData,
                                    0,
                                    chunkSize,
                                    AudioTrack.WRITE_BLOCKING
                            )

                    if (written != chunkSize) {
                        audioTrack.setPlaybackPositionUpdateListener(null)
                        val error = Exception("Failed to write entire audio chunk")
                        chunk.promise.reject("ERR_PLAYBACK", error.message, error)
                        continuation.resumeWith(Result.failure(error))
                    }

                    continuation.invokeOnCancellation {
                        audioTrack.setPlaybackPositionUpdateListener(null)
                    }
                }
            } catch (e: Exception) {
                chunk.promise.reject("ERR_PLAYBACK", e.message, e)
            }
        }
    }

    private fun convertPCMDataToFloatArray(pcmData: ByteArray): FloatArray {
        val shortBuffer = ByteBuffer.wrap(pcmData).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val shortArray = ShortArray(shortBuffer.remaining())
        shortBuffer.get(shortArray)
        return FloatArray(shortArray.size) { index -> shortArray[index] / 32768.0f }
    }

    private fun removeRIFFHeaderIfNeeded(audioData: ByteArray): ByteArray {
        val headerSize = 44
        val riffHeader = "RIFF".toByteArray(Charsets.US_ASCII)

        return if (audioData.size > headerSize && audioData.startsWith(riffHeader)) {
            audioData.copyOfRange(headerSize, audioData.size)
        } else {
            audioData
        }
    }

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean {
        if (this.size < prefix.size) return false
        return prefix.contentEquals(this.sliceArray(prefix.indices))
    }
}
