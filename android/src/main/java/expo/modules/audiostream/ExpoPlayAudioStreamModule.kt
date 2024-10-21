package expo.modules.audiostream

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.util.Base64
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import android.os.Bundle
import android.util.Log
import androidx.annotation.RequiresApi
import expo.modules.interfaces.permissions.Permissions
import android.Manifest
import java.util.ArrayDeque


class ExpoPlayAudioStreamModule : Module(), EventSender {
    data class ChunkData(val chunk: String, val turnId: String, val promise: Promise) // contains the base64 chunk
    data class AudioChunk(
            val audioData: FloatArray,
            val promise: Promise,
            var isPromiseSettled: Boolean = false
    ) // contains the decoded base64 chunk

    //private lateinit var processingChannel: Channel<ChunkData>
    private lateinit var processingQueue: ArrayDeque<ChunkData>
    private lateinit var playbackChannel: Channel<AudioChunk>

    private lateinit var audioRecorderManager: AudioRecorderManager

    private val coroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private var processingJob: Job? = null
    private var currentPlaybackJob: Job? = null

    private lateinit var audioTrack: AudioTrack
    private var isPlaying = false

    @RequiresApi(Build.VERSION_CODES.R)
    override fun definition() = ModuleDefinition {
        Name("ExpoPlayAudioStream")

        Events(Constants.AUDIO_EVENT_NAME)

        // Initialize AudioRecorderManager
        initializeManager()

        OnCreate {
            initializeAudioTrack()
            initializeChannels()
        }

        OnDestroy {
            stopPlayback()
            //processingChannel.close()
            processingQueue.clear()
            stopProcessingLoop()
            coroutineScope.cancel()
        }

        AsyncFunction("startRecording") { options: Map<String, Any?>, promise: Promise ->
            audioRecorderManager.startRecording(options, promise)
        }

        AsyncFunction("pauseRecording") { promise: Promise ->
            audioRecorderManager.pauseRecording(promise)
        }

        AsyncFunction("resumeRecording") { promise: Promise ->
            audioRecorderManager.resumeRecording(promise)
        }

        AsyncFunction("stopRecording") { promise: Promise ->
            audioRecorderManager.stopRecording(promise)
        }

        AsyncFunction("requestPermissionsAsync") { promise: Promise ->
            Permissions.askForPermissionsWithPermissionsManager(appContext.permissions, promise, Manifest.permission.RECORD_AUDIO)
        }

        AsyncFunction("getPermissionsAsync") { promise: Promise ->
            Permissions.getPermissionsWithPermissionsManager(appContext.permissions, promise, Manifest.permission.RECORD_AUDIO)
        }

        AsyncFunction("playAudio") { chunk: String, turnId:String, promise: Promise ->
            coroutineScope.launch {
                //if (processingChannel.isClosedForSend || playbackChannel.isClosedForSend) {
                if (processingQueue.isEmpty() || playbackChannel.isClosedForSend) {
                    initializeChannels()
                }
                //processingChannel.send(ChunkData(chunk, turnId, promise))
                processingQueue.add(ChunkData(chunk, turnId, promise))
                ensureProcessingLoopStarted()
            }
        }

        AsyncFunction("setVolume") { volume: Double, promise: Promise ->
            setVolume(volume, promise)
        }

        AsyncFunction("pauseAudio") { promise: Promise -> pausePlayback(promise) }

        AsyncFunction("stopAudio") { promise: Promise -> stopPlayback(promise) }

        AsyncFunction("clearPlaybackQueueByTurnId") { turnId:String, promise: Promise -> clearPlaybackQueueByTurnId(turnId, promise) }
    }
    private fun initializeManager() {
        val androidContext =
            appContext.reactContext ?: throw IllegalStateException("Android context not available")
        val permissionUtils = PermissionUtils(androidContext)
        val audioEncoder = AudioDataEncoder()
        audioRecorderManager =
            AudioRecorderManager(androidContext.filesDir, permissionUtils, audioEncoder, this)
    }

    override fun sendExpoEvent(eventName: String, params: Bundle) {
        Log.d(Constants.TAG, "Sending event: $eventName")
        this@ExpoPlayAudioStreamModule.sendEvent(eventName, params)
    }

    private fun initializeChannels() {
        //processingChannel = Channel<ChunkData>(Channel.UNLIMITED)
        processingQueue = ArrayDeque<ChunkData>()
        playbackChannel = Channel<AudioChunk>(Channel.UNLIMITED)
    }

    private fun ensureProcessingLoopStarted() {
        if (processingJob == null || processingJob?.isActive != true) {
            startProcessingLoop()
        }
    }

    private fun startProcessingLoop() {
        processingJob =
                coroutineScope.launch {
//                    for (chunkData in processingChannel) {
//                        processAndEnqueueChunk(chunkData)
//                        if (processingChannel.isEmpty && !isPlaying && playbackChannel.isEmpty) {
//                            break // Stop the loop if there's no more work to do
//                        }
//                    }

                    while (processingQueue.isNotEmpty()) {
                        val chunkData = processingQueue.poll() // Retrieve and remove the head of the queue
                        if (chunkData != null) {
                            processAndEnqueueChunk(chunkData)
                        } else {
                            // Handle the case where chunkData is null, if necessary
                            println("Encountered null chunkData, skipping.")
                        }

                        // If both queues are empty and no audio is playing, stop the loop
                        if (processingQueue.isEmpty() && !isPlaying && playbackChannel.isEmpty) {
                            break // Exit the loop
                        }
                    }
                    processingJob = null
                }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun clearPlaybackQueueByTurnId(turnId: String, promise: Promise? = null) {
        if (!processingQueue.isEmpty()) {
            processingQueue.removeIf { it.turnId == turnId }
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

            playbackChannel.send(AudioChunk(audioData, chunkData.promise))

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
                ensureProcessingLoopStarted()
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
            currentPlaybackJob = null

            // Resolve promises for any remaining chunks in the playback channel
            coroutineScope.launch {
                for (chunk in playbackChannel) {
                    if (!chunk.isPromiseSettled) {
                        chunk.isPromiseSettled = true
                        chunk.promise.resolve(null)
                    }
                }
            }

            // Cancel the processing job and close the channels
            processingJob?.cancel()
            processingJob = null
            //processingChannel.close()
            processingQueue.clear()
            playbackChannel.close()

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
                    playbackChannel.consumeAsFlow().collect { chunk ->
                        if (isPlaying) {
                            playChunk(chunk)
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
