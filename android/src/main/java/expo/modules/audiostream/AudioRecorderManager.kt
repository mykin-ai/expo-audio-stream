package expo.modules.audiostream

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.os.bundleOf
import expo.modules.kotlin.Promise
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean


class AudioRecorderManager(
    private val filesDir: File,
    private val permissionUtils: PermissionUtils,
    private val audioDataEncoder: AudioDataEncoder,
    private val eventSender: EventSender,
    private val audioEffectsManager: AudioEffectsManager
) {
    private var audioRecord: AudioRecord? = null
    private var bufferSizeInBytes = 1024
    private var isRecording = AtomicBoolean(false)
    private val isPaused = AtomicBoolean(false)
    private var streamUuid: String? = null
    private var audioFile: File? = null
    private var recordingThread: Thread? = null
    private var recordingStartTime: Long = 0
    private var totalRecordedTime: Long = 0
    private var totalDataSize = 0
    private var interval = 100L  // Emit data every 100 milliseconds (0.1 second)
    private var lastEmitTime = SystemClock.elapsedRealtime()
    private var lastPauseTime = 0L
    private var pausedDuration = 0L
    private var lastEmittedSize = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioRecordLock = Any()
    private var audioFileHandler: AudioFileHandler = AudioFileHandler(filesDir)
    
    // Flag to control whether actual audio data or silence is sent
    private var isSilent = false

    private lateinit var recordingConfig: RecordingConfig
    private var mimeType = "audio/wav"
    private var audioFormat: Int = AudioFormat.ENCODING_PCM_16BIT

    /**
     * Validates the recording state by checking permission and recording status
     * @param promise Promise to reject if validation fails
     * @param checkRecordingState Whether to check if recording is in progress
     * @param shouldRejectIfRecording Whether to reject if recording is in progress
     * @return True if validation passes, false otherwise
     */
    private fun validateRecordingState(
        promise: Promise? = null,
        checkRecordingState: Boolean = false,
        shouldRejectIfRecording: Boolean = true
    ): Boolean {
        // First check permission
        if (!permissionUtils.checkRecordingPermission()) {
            if (promise != null) {
                promise.reject("PERMISSION_DENIED", "Recording permission has not been granted", null)
            } else {
                throw SecurityException("Recording permission has not been granted")
            }
            return false
        }
        
        // Then check recording state if requested
        if (checkRecordingState) {
            val isActive = isRecording.get() && !isPaused.get()
            
            if (isActive && shouldRejectIfRecording && promise != null) {
                promise.resolve("Recording is already in progress")
                return false
            }
            
            return !isActive // Return true if not recording (validation passes)
        }
        
        return true // Permission check passed
    }

    @RequiresApi(Build.VERSION_CODES.R)
    fun startRecording(options: Map<String, Any?>, promise: Promise) {
        // Check permission and recording state
        if (!validateRecordingState(promise, checkRecordingState = true, shouldRejectIfRecording = true)) {
            return
        }

        // Initialize the recording configuration using the factory method
        val tempRecordingConfig = RecordingConfig.fromOptions(options)
        Log.d(Constants.TAG, "Initial recording configuration: $tempRecordingConfig")
        
        // Validate the recording configuration
        val configValidationResult = tempRecordingConfig.validate()
        if (configValidationResult != null) {
            promise.reject(configValidationResult.code, configValidationResult.message, null)
            return
        }

        // Get audio format configuration using the helper
        val formatConfig = audioDataEncoder.getAudioFormatConfig(tempRecordingConfig.encoding)
        
        // Check for any errors in the configuration
        if (formatConfig.error != null) {
            promise.reject("UNSUPPORTED_FORMAT", formatConfig.error, null)
            return
        }
        
        // Set the audio format
        audioFormat = formatConfig.audioFormat
        
        // Validate the audio format and get potentially updated config
        val formatValidationResult = validateAudioFormat(tempRecordingConfig, audioFormat, promise)
        if (formatValidationResult == null) {
            return
        }
        
        // Update with validated values
        audioFormat = formatValidationResult.first
        recordingConfig = formatValidationResult.second
        
        // Initialize the AudioRecord if it's a new recording or if it's not currently paused
        if (audioRecord == null || !isPaused.get()) {
            Log.d(Constants.TAG, "AudioFormat: $audioFormat, BufferSize: $bufferSizeInBytes")

            audioRecord = createAudioRecord(tempRecordingConfig, audioFormat, promise)
            if (audioRecord == null) {
                return
            }
        }
        // Create the audio file and write WAV header
        audioFile = createAndPrepareAudioFile(formatConfig.fileExtension, recordingConfig)
        if (audioFile == null) {
            promise.reject("FILE_CREATION_FAILED", "Failed to create the audio file", null)
            return
        }

        audioRecord?.startRecording()
        // Apply audio effects after starting recording using the manager
        audioRecord?.let { audioEffectsManager.setupAudioEffects(it) }
        
        isPaused.set(false)
        isRecording.set(true)

        if (!isPaused.get()) {
            recordingStartTime =
                System.currentTimeMillis() // Only reset start time if it's not a resume
        }

        recordingThread = Thread { recordingProcess() }.apply { start() }

        val result = bundleOf(
            "fileUri" to audioFile?.toURI().toString(),
            "channels" to recordingConfig.channels,
            "bitDepth" to when (recordingConfig.encoding) {
                "pcm_8bit" -> 8
                "pcm_16bit" -> 16
                "pcm_32bit" -> 32
                else -> 16 // Default to 16 if the encoding is not recognized
            },
            "sampleRate" to recordingConfig.sampleRate,
            "mimeType" to formatConfig.mimeType
        )
        promise.resolve(result)
    }

    /**
     * Common resource cleanup logic extracted to avoid duplication
     */
    private fun cleanupResources() {
        try {
            // Release audio effects
            audioEffectsManager.releaseAudioEffects()
            
            // Stop and release AudioRecord if exists
            if (audioRecord != null) {
                try {
                    if (audioRecord!!.state == AudioRecord.STATE_INITIALIZED) {
                        audioRecord!!.stop()
                    }
                } catch (e: Exception) {
                    Log.e(Constants.TAG, "Error stopping AudioRecord", e)
                } finally {
                    try {
                        audioRecord!!.release()
                    } catch (e: Exception) {
                        Log.e(Constants.TAG, "Error releasing AudioRecord", e)
                    }
                }
                audioRecord = null
            }
            
            // Interrupt and clear recording thread
            recordingThread?.interrupt()
            recordingThread = null
            
            // Always reset state
            isRecording.set(false)
            isPaused.set(false)
            totalRecordedTime = 0
            pausedDuration = 0
            totalDataSize = 0
            streamUuid = null
            lastEmitTime = SystemClock.elapsedRealtime()
            lastEmittedSize = 0
            
            Log.d(Constants.TAG, "Audio resources cleaned up")
        } catch (e: Exception) {
            Log.e(Constants.TAG, "Error during resource cleanup", e)
        }
    }

    fun stopRecording(promise: Promise) {
        synchronized(audioRecordLock) {
            if (!isRecording.get()) {
                Log.e(Constants.TAG, "Recording is not active")
                promise.resolve(null)
                return
            }

            try {
                // Read any final audio data
                val audioData = ByteArray(bufferSizeInBytes)
                val bytesRead = audioRecord?.read(audioData, 0, bufferSizeInBytes) ?: -1
                Log.d(Constants.TAG, "Last Read $bytesRead bytes")
                if (bytesRead > 0) {
                    emitAudioData(audioData, bytesRead)
                }
                
                // Generate result before cleanup
                val fileSize = audioFile?.length() ?: 0
                val dataFileSize = fileSize - 44  // Subtract header size
                val byteRate = recordingConfig.sampleRate * recordingConfig.channels * when (recordingConfig.encoding) {
                    "pcm_8bit" -> 1
                    "pcm_16bit" -> 2
                    "pcm_32bit" -> 4
                    else -> 2 // Default to 2 bytes per sample if the encoding is not recognized
                }
                // Calculate duration based on the data size and byte rate
                val duration = if (byteRate > 0) (dataFileSize * 1000 / byteRate) else 0

                // Create result bundle
                val result = bundleOf(
                    "fileUri" to audioFile?.toURI().toString(),
                    "filename" to audioFile?.name,
                    "durationMs" to duration,
                    "channels" to recordingConfig.channels,
                    "bitDepth" to when (recordingConfig.encoding) {
                        "pcm_8bit" -> 8
                        "pcm_16bit" -> 16
                        "pcm_32bit" -> 32
                        else -> 16 // Default to 16 if the encoding is not recognized
                    },
                    "sampleRate" to recordingConfig.sampleRate,
                    "size" to fileSize,
                    "mimeType" to mimeType
                )
                
                // Clean up all resources
                cleanupResources()
                
                // Resolve promise with the result
                promise.resolve(result)
                
            } catch (e: Exception) {
                Log.d(Constants.TAG, "Failed to stop recording", e)
                // Make sure to clean up even if there's an error
                cleanupResources()
                promise.reject("STOP_FAILED", "Failed to stop recording", e)
            }
        }
    }

    fun pauseRecording(promise: Promise) {
        if (isRecording.get() && !isPaused.get()) {
            // Release audio effects when pausing using the manager
            audioEffectsManager.releaseAudioEffects()
            
            audioRecord?.stop()
            lastPauseTime =
                System.currentTimeMillis()  // Record the time when the recording was paused
            isPaused.set(true)
            promise.resolve("Recording paused")
        } else {
            promise.reject(
                "NOT_RECORDING_OR_ALREADY_PAUSED",
                "Recording is either not active or already paused",
                null
            )
        }
    }

    fun resumeRecording(promise: Promise) {
        if (isRecording.get() && !isPaused.get()) {
            promise.reject("NOT_PAUSED", "Recording is not paused", null)
            return
        } else if (audioRecord == null) {
            promise.reject("NOT_RECORDING", "Recording is not active", null)
        }

        // Calculate the duration the recording was paused
        pausedDuration += System.currentTimeMillis() - lastPauseTime
        isPaused.set(false)
        audioRecord?.startRecording()
        
        // Re-apply audio effects when resuming using the manager
        audioRecord?.let { audioEffectsManager.setupAudioEffects(it) }
        
        promise.resolve("Recording resumed")
    }

    fun listAudioFiles(promise: Promise) {
        val fileList =
            filesDir.list()?.filter { it.endsWith(".wav") }?.map { File(filesDir, it).absolutePath }
                ?: listOf()
        promise.resolve(fileList)
    }

    fun clearAudioStorage(promise: Promise) {
        audioFileHandler.clearAudioStorage()
        promise.resolve(null)
    }

    private fun recordingProcess() {
        Log.i(Constants.TAG, "Starting recording process...")
        FileOutputStream(audioFile, true).use { fos ->
            // Buffer to accumulate data
            val accumulatedAudioData = ByteArrayOutputStream()
            audioFileHandler.writeWavHeader(
                accumulatedAudioData,
                recordingConfig.sampleRate,
                recordingConfig.channels,
                when (recordingConfig.encoding) {
                    "pcm_8bit" -> 8
                    "pcm_16bit" -> 16
                    "pcm_32bit" -> 32
                    else -> 16 // Default to 16 if the encoding is not recognized
                }
            )
            // Write audio data directly to the file
            val audioData = ByteArray(bufferSizeInBytes)
            Log.d(Constants.TAG, "Entering recording loop")
            while (isRecording.get() && !Thread.currentThread().isInterrupted) {
                if (isPaused.get()) {
                    // If recording is paused, skip reading from the microphone
                    continue
                }

                val bytesRead = synchronized(audioRecordLock) {
                    // Only synchronize the read operation and the check
                    audioRecord?.let {
                        if (it.state != AudioRecord.STATE_INITIALIZED) {
                            Log.e(Constants.TAG, "AudioRecord not initialized")
                            return@let -1
                        }
                        it.read(audioData, 0, bufferSizeInBytes).also { bytes ->
                            if (bytes < 0) {
                                Log.e(Constants.TAG, "AudioRecord read error: $bytes")
                            }
                        }
                    } ?: -1 // Handle null case
                }
                if (bytesRead > 0) {
                    fos.write(audioData, 0, bytesRead)
                    totalDataSize += bytesRead
                    accumulatedAudioData.write(audioData, 0, bytesRead)

                    // Emit audio data at defined intervals
                    if (SystemClock.elapsedRealtime() - lastEmitTime >= interval) {
                        emitAudioData(
                            accumulatedAudioData.toByteArray(),
                            accumulatedAudioData.size()
                        )
                        lastEmitTime = SystemClock.elapsedRealtime() // Reset the timer
                        accumulatedAudioData.reset() // Clear the accumulator
                    }

                    Log.d(Constants.TAG, "Bytes written to file: $bytesRead")
                }
            }
        }
        // Update the WAV header to reflect the actual data size
        audioFile?.let { file ->
            audioFileHandler.updateWavHeader(file)
        }
    }

    private fun emitAudioData(audioData: ByteArray, length: Int) {
        // If silent mode is active, replace audioData with zeros (using concise expression)
        val dataToEncode = if (isSilent) ByteArray(length) else audioData
        
        val encodedBuffer = audioDataEncoder.encodeToBase64(dataToEncode)

        val fileSize = audioFile?.length() ?: 0
        val from = lastEmittedSize
        val deltaSize = fileSize - lastEmittedSize
        lastEmittedSize = fileSize

        // Calculate position in milliseconds
        val positionInMs = (from * 1000) / (recordingConfig.sampleRate * recordingConfig.channels * (if (recordingConfig.encoding == "pcm_8bit") 8 else 16) / 8)

        // Calculate power level (using concise expression)
        val soundLevel = if (isSilent) -160.0f else audioDataEncoder.calculatePowerLevel(audioData, length)

        mainHandler.post {
            try {
                eventSender.sendExpoEvent(
                    Constants.AUDIO_EVENT_NAME, bundleOf(
                        "fileUri" to audioFile?.toURI().toString(),
                        "lastEmittedSize" to from,
                        "encoded" to encodedBuffer,
                        "deltaSize" to length,
                        "position" to positionInMs,
                        "mimeType" to mimeType,
                        "soundLevel" to soundLevel,
                        "totalSize" to fileSize,
                        "streamUuid" to streamUuid
                    )
                )
            } catch (e: Exception) {
                Log.e(Constants.TAG, "Failed to send event", e)
            }
        }
    }

    /**
     * Releases all resources used by the recorder.
     * Should be called when the module is being destroyed.
     */
    fun release() {
        try {
            // If recording is active, stop it properly
            if (isRecording.get()) {
                // Create a simple promise to handle the result without callback
                val dummyPromise = object : Promise {
                    override fun resolve(value: Any?) {
                        Log.d(Constants.TAG, "Recording stopped during release")
                    }
                    
                    override fun reject(code: String, message: String?, cause: Throwable?) {
                        Log.e(Constants.TAG, "Error stopping recording during release: $message", cause)
                    }
                }
                
                // Use stopRecording which will handle full cleanup
                stopRecording(dummyPromise)
            } else {
                // Not recording, just clean up resources
                cleanupResources()
            }
            
            Log.d(Constants.TAG, "AudioRecorderManager fully released")
        } catch (e: Exception) {
            Log.e(Constants.TAG, "Error during AudioRecorderManager release", e)
        }
    }

    /**
     * Toggles between sending actual audio data and silence
     */
    fun toggleSilence() {
        isSilent = !isSilent
        Log.d(Constants.TAG, "Silence mode toggled: $isSilent")
    }

    /**
     * Creates an AudioRecord instance with the given configuration
     * @param config The recording configuration
     * @param audioFormat The audio format to use
     * @param promise Promise to reject if initialization fails
     * @return The created AudioRecord instance or null if failed
     */
    private fun createAudioRecord(
        config: RecordingConfig,
        audioFormat: Int,
        promise: Promise
    ): AudioRecord? {
        // Double check permission again directly before creating AudioRecord
        if (!permissionUtils.checkRecordingPermission()) {
            promise.reject("PERMISSION_DENIED", "Recording permission has not been granted", null)
            return null
        }
        
        // Always use VOICE_COMMUNICATION for better echo cancellation
        val audioSource = MediaRecorder.AudioSource.VOICE_COMMUNICATION
        
        val record = AudioRecord(
            audioSource, // Using VOICE_COMMUNICATION for built-in echo cancellation
            config.sampleRate,
            if (config.channels == 1) AudioFormat.CHANNEL_IN_MONO else AudioFormat.CHANNEL_IN_STEREO,
            audioFormat,
            bufferSizeInBytes
        )
        
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            promise.reject(
                "INITIALIZATION_FAILED",
                "Failed to initialize the audio recorder",
                null
            )
            return null
        }
        
        return record
    }

    /**
     * Creates a new audio file with a unique identifier and writes the WAV header
     * @param fileExtension The file extension to use
     * @param config The recording configuration
     * @return The created File object or null if creation failed
     */
    private fun createAndPrepareAudioFile(fileExtension: String, config: RecordingConfig): File? {
        // Generate a unique ID for this recording
        val uuid = java.util.UUID.randomUUID().toString()
        streamUuid = uuid
        
        // Create the file
        val file = File(filesDir, "audio_${uuid}.${fileExtension}")
        
        // Write the WAV header
        try {
            FileOutputStream(file, true).use { fos ->
                audioFileHandler.writeWavHeader(fos, config.sampleRate, config.channels, when (config.encoding) {
                    "pcm_8bit" -> 8
                    "pcm_16bit" -> 16
                    "pcm_32bit" -> 32
                    else -> 16 // Default to 16 if the encoding is not recognized
                })
            }
            return file
        } catch (e: IOException) {
            Log.e(Constants.TAG, "Failed to create and prepare audio file", e)
            return null
        }
    }

    /**
     * Validates the audio format for the given recording configuration
     * @param config The recording configuration
     * @param initialFormat The initial audio format to validate
     * @param promise Promise to reject if no supported format is found
     * @return A pair containing the validated audio format and potentially updated recording config
     */
    private fun validateAudioFormat(
        config: RecordingConfig,
        initialFormat: Int,
        promise: Promise
    ): Pair<Int, RecordingConfig>? {
        var audioFormat = initialFormat
        var updatedConfig = config
        
        // Check if selected audio format is supported
        if (!audioDataEncoder.isAudioFormatSupported(config.sampleRate, config.channels, audioFormat, permissionUtils)) {
            Log.e(Constants.TAG, "Selected audio format not supported, falling back to 16-bit PCM")
            audioFormat = AudioFormat.ENCODING_PCM_16BIT
            
            if (!audioDataEncoder.isAudioFormatSupported(config.sampleRate, config.channels, audioFormat, permissionUtils)) {
                promise.reject("INITIALIZATION_FAILED", "Failed to initialize audio recorder with any supported format", null)
                return null
            }
            
            updatedConfig = config.copy(encoding = "pcm_16bit")
        }
        
        return Pair(audioFormat, updatedConfig)
    }
}