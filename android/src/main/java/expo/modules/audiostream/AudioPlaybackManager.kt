package expo.modules.audiostream

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Base64
import android.util.Log
import expo.modules.kotlin.Promise
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.max
import kotlin.math.min

data class ChunkData(val chunk: String, val turnId: String, val promise: Promise) // contains the base64 chunk
data class AudioChunk(
    val audioData: FloatArray,
    val promise: Promise,
    val turnId: String,
    var isPromiseSettled: Boolean = false
) // contains the decoded base64 chunk

class AudioPlaybackManager() {
    private lateinit var processingChannel: Channel<ChunkData>
    private lateinit var playbackChannel: Channel<AudioChunk>

    private val coroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private var processingJob: Job? = null
    private var currentPlaybackJob: Job? = null

    private lateinit var audioTrack: AudioTrack
    private var isPlaying = false
    private var isMuted = false
    private var currentTurnId: String? = null

    init {
        initializeAudioTrack()
        initializeChannels()
    }

    fun playAudio(chunk: String, turnId: String, promise: Promise) {
        coroutineScope.launch {
            if (processingChannel.isClosedForSend || playbackChannel.isClosedForSend) {
                Log.d("ExpoPlayStreamModule", "Re-initializing channels")
                initializeChannels()
            }
            Log.d("ExpoPlayStreamModule", "PlayAudio input $turnId and current id $currentTurnId")
            currentTurnId = turnId
            isMuted = false
            processingChannel.send(ChunkData(chunk, turnId, promise))
            ensureProcessingLoopStarted()
        }
    }

    fun setCurrentTurnId(turnId: String) {
        currentTurnId = turnId
    }

    private fun initializeChannels() {
        // Close the channels if they are still open
        if (!::processingChannel.isInitialized || processingChannel.isClosedForSend) {
            processingChannel = Channel(Channel.UNLIMITED)
        }
        if (!::playbackChannel.isInitialized || playbackChannel.isClosedForSend) {
            playbackChannel = Channel(Channel.UNLIMITED)
        }
    }

    fun runOnDispose() {
        stopPlayback()
        processingChannel.close()
        stopProcessingLoop()
        coroutineScope.cancel()
    }

    fun stopProcessingLoop() {
        processingJob?.cancel()
        processingJob = null
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
                    Log.d("ExpoPlayStreamModule", "Received TurnId ${chunkData.turnId} and current id $currentTurnId and playback is Muted $isMuted")
                    if (chunkData.turnId == currentTurnId) {
                        processAndEnqueueChunk(chunkData)
                    }

                    if (processingChannel.isEmpty && !isPlaying && playbackChannel.isEmpty) {
                        break // Stop the loop if there's no more work to do
                    }
                }
                Log.d("ExpoPlayStreamModule", "Clear Processing JOB")
                processingJob = null
            }
    }

    private suspend fun processAndEnqueueChunk(chunkData: ChunkData) {
        try {
            val decodedBytes = Base64.decode(chunkData.chunk, Base64.DEFAULT)
            val audioDataWithoutRIFF = removeRIFFHeaderIfNeeded(decodedBytes)
            val audioData = convertPCMDataToFloatArray(audioDataWithoutRIFF)

            playbackChannel.send(
                AudioChunk(
                    audioData,
                    chunkData.promise,
                    chunkData.turnId
                )
            )

            if (!isPlaying) {
                Log.d("ExpoPlayStreamModule", "Start Playback")
                startPlayback()
            }
        } catch (e: Exception) {
            chunkData.promise.reject("ERR_PROCESSING_AUDIO", e.message, e)
        }
    }

    fun setVolume(volume: Double, promise: Promise) {
        val clampedVolume = max(0.0, min(volume, 100.0)) / 100.0
        try {
            audioTrack.setVolume(clampedVolume.toFloat())
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject("ERR_SET_VOLUME", e.message, e)
        }
    }

    fun mutePlayback(promise: Promise) {
        Log.d("ExpoPlayStreamModule", "Mute Playback")
        isMuted = true
        promise.resolve(null)
    }

    fun pausePlayback(promise: Promise? = null, isFlushAudioTrack: Boolean = false) {
        try {
            audioTrack.pause()
            if (isFlushAudioTrack) {
                audioTrack.flush()
            }
            isPlaying = false
            currentPlaybackJob?.cancel()
            promise?.resolve(null)
        } catch (e: Exception) {
            promise?.reject("ERR_PAUSE_PLAYBACK", e.message, e)
        }
    }

    fun startPlayback(promise: Promise? = null) {
        try {
            if (!isPlaying) {
                audioTrack.play()
                isPlaying = true
                Log.d("ExpoPlayStreamModule", "Starting Playback Loop")
                startPlaybackLoop()
                Log.d("ExpoPlayStreamModule", "Ensure processing Loop Started in startPlayback")
                ensureProcessingLoopStarted()
            }
            promise?.resolve(null)
        } catch (e: Exception) {
            promise?.reject("ERR_START_PLAYBACK", e.message, e)
        }
    }

    fun stopPlayback(promise: Promise? = null) {
        Log.d("ExpoPlayStreamModule", "Stopping playback")
        if (!isPlaying || playbackChannel.isEmpty ) {
            promise?.resolve(null)
            Log.d("ExpoPlayStreamModule", "Nothing is played return")
            return
        }
        isPlaying = false
        coroutineScope.launch {
            try {

                Log.d("ExpoPlayStreamModule", "Stopping audioTrack")
                audioTrack.stop()
                Log.d("ExpoPlayStreamModule", "Flushing audioTrack")
                audioTrack.flush()
                // Safely cancel jobs
                if (currentPlaybackJob != null) {
                    Log.d("ExpoPlayStreamModule", "Cancelling currentPlaybackJob")
                    currentPlaybackJob?.cancelAndJoin()  // Add logging here to trace progress
                    currentPlaybackJob = null
                }

                if (processingJob != null) {
                    Log.d("ExpoPlayStreamModule", "Cancelling processingJob")
                    processingJob?.cancelAndJoin()  // Add logging here to trace progress
                    processingJob = null
                }

                // Resolve remaining promises in playbackChannel
                Log.d("ExpoPlayStreamModule", "Resolving remaining promises in playbackChannel")
                for (chunk in playbackChannel) {
                    Log.d("ExpoPlayStreamModule", "New chunk $chunk")
                    if (!chunk.isPromiseSettled) {
                        chunk.isPromiseSettled = true
                        chunk.promise.resolve(null)
                    }
                }

                Log.d("ExpoPlayStreamModule", "Closing the channels")

                if (!processingChannel.isClosedForSend) {
                    Log.d("ExpoPlayStreamModule", "Closing processingChannel")
                    processingChannel.close()
                } else {
                    Log.d("ExpoPlayStreamModule", "Processing channel is already closed")
                }

                Log.d("ExpoPlayStreamModule", "Checking if playbackChannel is closed")
                if (!playbackChannel.isClosedForSend) {
                    Log.d("ExpoPlayStreamModule", "Closing playbackChannel")
                    playbackChannel.close()
                } else {
                    Log.d("ExpoPlayStreamModule", "Playback channel is already closed")
                }

                Log.d("ExpoPlayStreamModule", "Stopped")
                promise?.resolve(null)
            } catch (e: CancellationException) {
                Log.d("ExpoPlayStreamModule", "Stop playback was cancelled: ${e.message}")
                promise?.resolve(null)
            } catch (e: Exception) {
                Log.d("ExpoPlayStreamModule", "Error in stopPlayback: ${e.message}")
                promise?.reject("ERR_STOP_PLAYBACK", e.message, e)
            }
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
                playbackChannel.consumeAsFlow().collect { chunk ->
                    if (isPlaying) {
                        Log.d("ExpoPlayStreamModule", "Playing chunk : $chunk")
                        if (currentTurnId == chunk.turnId) {
                            playChunk(chunk)
                        }

                    } else {
                        // If not playing, we should resolve the promise to avoid leaks
                        chunk.promise.resolve(null)
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
                                if (!chunk.isPromiseSettled) {
                                    chunk.isPromiseSettled = true
                                    chunk.promise.resolve(null)
                                }
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

                    Log.d("ExpoPlayStreamModule", "Chunk played : $written")
                    if (written != chunkSize) {
                        audioTrack.setPlaybackPositionUpdateListener(null)
                        val error = Exception("Failed to write entire audio chunk")
                        if (!chunk.isPromiseSettled) {
                            chunk.isPromiseSettled = true
                            //                            chunk.promise.reject("ERR_PLAYBACK",
                            // error.message, error)
                            chunk.promise.resolve(null)
                        }
                        continuation.resumeWith(Result.failure(error))
                    }

                    continuation.invokeOnCancellation {
                        audioTrack.setPlaybackPositionUpdateListener(null)
                        if (!chunk.isPromiseSettled) {
                            chunk.isPromiseSettled = true
                            chunk.promise.reject(
                                "ERR_PLAYBACK_CANCELLED",
                                "Playback was cancelled",
                                null
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                if (!chunk.isPromiseSettled) {
                    chunk.isPromiseSettled = true
                    chunk.promise.reject("ERR_PLAYBACK", e.message, e)
                }
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