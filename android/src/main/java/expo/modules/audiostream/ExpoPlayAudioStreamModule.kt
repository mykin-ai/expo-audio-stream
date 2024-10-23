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

        Events(Constants.AUDIO_EVENT_NAME)

        // Initialize managers for playback and for recording
        initializeManager()
        initializePlaybackManager()

        OnCreate {
        }

        OnDestroy {
            audioPlaybackManager.runOnDispose()
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

        AsyncFunction("playAudio") { chunk: String, turnId: String, promise: Promise ->
            audioPlaybackManager.playAudio(chunk, turnId, promise)
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
        audioPlaybackManager = AudioPlaybackManager()
    }

    override fun sendExpoEvent(eventName: String, params: Bundle) {
        Log.d(Constants.TAG, "Sending event EXPO: $eventName")
        this@ExpoPlayAudioStreamModule.sendEvent(eventName, params)
    }
}
