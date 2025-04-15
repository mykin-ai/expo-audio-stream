package expo.modules.audiostream

import android.os.Build
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import android.os.Bundle
import android.util.Log
import androidx.annotation.RequiresApi
import expo.modules.interfaces.permissions.Permissions
import android.Manifest


class ExpoPlayAudioStreamModule : Module(), EventSender {
    private lateinit var audioRecorderManager: AudioRecorderManager
    private lateinit var audioPlaybackManager: AudioPlaybackManager

    @RequiresApi(Build.VERSION_CODES.R)
    override fun definition() = ModuleDefinition {
        Name("ExpoPlayAudioStream")

        Events(
            Constants.AUDIO_EVENT_NAME,
            Constants.SOUND_CHUNK_PLAYED_EVENT_NAME,
            Constants.SOUND_STARTED_EVENT_NAME,
            Constants.DEVICE_RECONNECTED_EVENT_NAME
        )

        // Initialize managers for playback and for recording
        initializeManager()
        initializePlaybackManager()

        OnCreate {
        }

        OnDestroy {
            audioPlaybackManager.runOnDispose()
        }

        Function("destroy") {
            audioPlaybackManager.runOnDispose()
            initializeManager()
            initializePlaybackManager()
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
            Permissions.askForPermissionsWithPermissionsManager(
                appContext.permissions,
                promise,
                Manifest.permission.RECORD_AUDIO
            )
        }

        AsyncFunction("getPermissionsAsync") { promise: Promise ->
            Permissions.getPermissionsWithPermissionsManager(
                appContext.permissions,
                promise,
                Manifest.permission.RECORD_AUDIO
            )
        }

        AsyncFunction("playAudio") { chunk: String, turnId: String, encoding: String?, promise: Promise ->
            val pcmEncoding = when (encoding) {
                "pcm_f32le" -> PCMEncoding.PCM_F32LE
                "pcm_s16le", null -> PCMEncoding.PCM_S16LE
                else -> {
                    Log.d(Constants.TAG, "Unsupported encoding: $encoding, defaulting to PCM_S16LE")
                    PCMEncoding.PCM_S16LE
                }
            }
            audioPlaybackManager.playAudio(chunk, turnId, promise, pcmEncoding)
        }

        AsyncFunction("clearPlaybackQueueByTurnId") { turnId: String, promise: Promise ->
            audioPlaybackManager.setCurrentTurnId(turnId)
            promise.resolve(null)
        }

        AsyncFunction("setVolume") { volume: Double, promise: Promise ->
            audioPlaybackManager.setVolume(volume, promise)
        }

        AsyncFunction("pauseAudio") { promise: Promise -> audioPlaybackManager.stopPlayback(promise) }

        AsyncFunction("stopAudio") { promise: Promise -> audioPlaybackManager.stopPlayback(promise) }

        AsyncFunction("clearAudioFiles") { promise: Promise ->
            audioRecorderManager.clearAudioStorage(promise)
        }

        AsyncFunction("listAudioFiles") { promise: Promise ->
            audioRecorderManager.listAudioFiles(promise)
        }

        AsyncFunction("playSound") { chunk: String, turnId: String, encoding: String?, promise: Promise ->
            val pcmEncoding = when (encoding) {
                "pcm_f32le" -> PCMEncoding.PCM_F32LE
                "pcm_s16le", null -> PCMEncoding.PCM_S16LE
                else -> {
                    Log.d(Constants.TAG, "Unsupported encoding: $encoding, defaulting to PCM_S16LE")
                    PCMEncoding.PCM_S16LE
                }
            }
            audioPlaybackManager.playAudio(chunk, turnId, promise, pcmEncoding)
        }

        AsyncFunction("playWav") { chunk: String, promise: Promise ->
            audioPlaybackManager.playAudio(chunk, AudioPlaybackManager.SUSPEND_SOUND_EVENT_TURN_ID, promise)
        }

        AsyncFunction("stopSound") { promise: Promise -> audioPlaybackManager.stopPlayback(promise) }

        AsyncFunction("interruptSound") { promise: Promise -> audioPlaybackManager.stopPlayback(promise) }

        Function("resumeSound") {
            // not applicable for android
        }

        AsyncFunction("clearSoundQueueByTurnId") { turnId: String, promise: Promise ->
            audioPlaybackManager.setCurrentTurnId(turnId)
            promise.resolve(null)
        }

        AsyncFunction("startMicrophone") { options: Map<String, Any?>, promise: Promise ->
            audioRecorderManager.startRecording(options, promise)
        }

        AsyncFunction("stopMicrophone") { promise: Promise ->
            audioRecorderManager.stopRecording(promise)
        }

        Function("toggleSilence") {
            // not applicable for android
        }

        AsyncFunction("setSoundConfig") { config: Map<String, Any?>, promise: Promise ->
            val useDefault = config["useDefault"] as? Boolean ?: false
            
            if (useDefault) {
                // Reset to default configuration
                Log.d(Constants.TAG, "Resetting sound configuration to default values")
                audioPlaybackManager.resetConfigToDefault(promise)
            } else {
                // Extract configuration values
                val sampleRate = (config["sampleRate"] as? Number)?.toInt() ?: 16000
                val playbackModeString = config["playbackMode"] as? String ?: "regular"
                
                // Convert string playback mode to enum
                val playbackMode = when (playbackModeString) {
                    "voiceProcessing" -> PlaybackMode.VOICE_PROCESSING
                    "conversation" -> PlaybackMode.CONVERSATION
                    else -> PlaybackMode.REGULAR
                }
                
                // Create a new SoundConfig object
                val soundConfig = SoundConfig(sampleRate = sampleRate, playbackMode = playbackMode)
                
                // Update the sound player configuration
                Log.d(Constants.TAG, "Setting sound configuration - sampleRate: $sampleRate, playbackMode: $playbackModeString")
                audioPlaybackManager.updateConfig(soundConfig, promise)
            }
        }

    }
    private fun initializeManager() {
        val androidContext =
            appContext.reactContext ?: throw IllegalStateException("Android context not available")
        val permissionUtils = PermissionUtils(androidContext)
        val audioEncoder = AudioDataEncoder()
        audioRecorderManager =
            AudioRecorderManager(androidContext.filesDir, permissionUtils, audioEncoder, this)
    }

    private fun initializePlaybackManager() {
        audioPlaybackManager = AudioPlaybackManager(this)
    }

    override fun sendExpoEvent(eventName: String, params: Bundle) {
        Log.d(Constants.TAG, "Sending event EXPO: $eventName")
        this@ExpoPlayAudioStreamModule.sendEvent(eventName, params)
    }
}
