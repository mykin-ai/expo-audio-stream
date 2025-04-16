package expo.modules.audiostream

import android.Manifest
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.RequiresApi
import expo.modules.interfaces.permissions.Permissions
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition


class ExpoPlayAudioStreamModule : Module(), EventSender {
    private lateinit var audioRecorderManager: AudioRecorderManager
    private lateinit var audioPlaybackManager: AudioPlaybackManager
    private lateinit var wavAudioPlayer: WavAudioPlayer

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
        initializeWavPlayer()

        OnCreate {
        }

        OnDestroy {
            // Module is being destroyed (app shutdown)
            // Just clean up resources without reinitialization
            audioPlaybackManager.runOnDispose()
            wavAudioPlayer.release()
            audioRecorderManager.release()
        }

        Function("destroy") {
            // User explicitly called destroy - clean up and reinitialize for reuse
            audioPlaybackManager.runOnDispose()
            wavAudioPlayer.release()
            audioRecorderManager.release()
            
            // Reinitialize all managers so the module can be used again
            initializeManager()
            initializePlaybackManager()
            initializeWavPlayer()
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
            wavAudioPlayer.playWavFile(chunk, promise)
        }

        AsyncFunction("stopWav") { promise: Promise ->
            wavAudioPlayer.stopWavPlayback(promise)
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
            // Just toggle silence without returning any value
            audioRecorderManager.toggleSilence()
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
        val audioEffectsManager = AudioEffectsManager()
        audioRecorderManager =
            AudioRecorderManager(
                androidContext.filesDir,
                permissionUtils, 
                audioEncoder, 
                this,
                audioEffectsManager
            )
    }

    private fun initializePlaybackManager() {
        audioPlaybackManager = AudioPlaybackManager(this)
    }

    private fun initializeWavPlayer() {
        wavAudioPlayer = WavAudioPlayer()
    }

    override fun sendExpoEvent(eventName: String, params: Bundle) {
        Log.d(Constants.TAG, "Sending event EXPO: $eventName")
        this@ExpoPlayAudioStreamModule.sendEvent(eventName, params)
    }
}
