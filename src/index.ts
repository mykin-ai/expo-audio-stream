import { Subscription } from "expo-modules-core";
import ExpoPlayAudioStreamModule from "./ExpoPlayAudioStreamModule";
import {
  AudioDataEvent,
  AudioRecording,
  RecordingConfig,
  StartRecordingResult,
  SoundConfig,
  PlaybackMode,
  Encoding,
  EncodingTypes,
  PlaybackModes,
} from "./types";

import {
  addAudioEventListener,
  addSoundChunkPlayedListener,
  AudioEventPayload,
  SoundChunkPlayedEventPayload,
  AudioEvents,
  subscribeToEvent,
  DeviceReconnectedReason,
  DeviceReconnectedEventPayload,
} from "./events";

const SuspendSoundEventTurnId = "suspend-sound-events";

export class ExpoPlayAudioStream {
  /**
   * Destroys the audio stream module, cleaning up all resources.
   * This should be called when the module is no longer needed.
   * It will reset all internal state and release audio resources.
   */
  static destroy() {
    ExpoPlayAudioStreamModule.destroy();
  }

  /**
   * Starts microphone recording.
   * @param {RecordingConfig} recordingConfig - Configuration for the recording.
   * @returns {Promise<{recordingResult: StartRecordingResult, subscription: Subscription}>} A promise that resolves to an object containing the recording result and a subscription to audio events.
   * @throws {Error} If the recording fails to start.
   */
  static async startRecording(recordingConfig: RecordingConfig): Promise<{
    recordingResult: StartRecordingResult;
    subscription?: Subscription;
  }> {
    const { onAudioStream, ...options } = recordingConfig;

    let subscription: Subscription | undefined;

    if (onAudioStream && typeof onAudioStream == "function") {
      subscription = addAudioEventListener(async (event: AudioEventPayload) => {
        const { fileUri, deltaSize, totalSize, position, encoded, soundLevel } =
          event;
        if (!encoded) {
          console.error(`[ExpoPlayAudioStream] Encoded audio data is missing`);
          throw new Error("Encoded audio data is missing");
        }
        onAudioStream?.({
          data: encoded,
          position,
          fileUri,
          eventDataSize: deltaSize,
          totalSize,
          soundLevel,
        });
      });
    }

    try {
      const recordingResult = await ExpoPlayAudioStreamModule.startRecording(
        options
      );
      return { recordingResult, subscription };
    } catch (error) {
      console.error(error);
      subscription?.remove();
      throw new Error(`Failed to start recording: ${error}`);
    }
  }

  /**
   * Stops the current microphone recording.
   * @returns {Promise<AudioRecording>} A promise that resolves to the audio recording data.
   * @throws {Error} If the recording fails to stop.
   */
  static async stopRecording(): Promise<AudioRecording> {
    try {
      return await ExpoPlayAudioStreamModule.stopRecording();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stop recording: ${error}`);
    }
  }

  /**
   * Plays an audio chunk.
   * @param {string} base64Chunk - The base64 encoded audio chunk to play.
   * @param {string} turnId - The turn ID.
   * @param {string} [encoding] - The encoding format of the audio data ('pcm_f32le' or 'pcm_s16le').
   * @returns {Promise<void>}
   * @throws {Error} If the audio chunk fails to stream.
   */
  static async playAudio(
    base64Chunk: string,
    turnId: string,
    encoding?: Encoding
  ): Promise<void> {
    try {
      return ExpoPlayAudioStreamModule.playAudio(
        base64Chunk,
        turnId,
        encoding ?? EncodingTypes.PCM_S16LE
      );
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stream audio chunk: ${error}`);
    }
  }

  /**
   * Pauses the current audio playback.
   * @returns {Promise<void>}
   * @throws {Error} If the audio playback fails to pause.
   */
  static async pauseAudio(): Promise<void> {
    try {
      return await ExpoPlayAudioStreamModule.pauseAudio();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to pause audio: ${error}`);
    }
  }

  /**
   * Stops the currently playing audio.
   * @returns {Promise<void>}
   * @throws {Error} If the audio fails to stop.
   */
  static async stopAudio(): Promise<void> {
    try {
      return await ExpoPlayAudioStreamModule.stopAudio();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stop audio: ${error}`);
    }
  }

  /**
   * Clears the playback queue by turn ID.
   * @param {string} turnId - The turn ID.
   * @returns {Promise<void>}
   * @throws {Error} If the playback queue fails to clear.
   */
  static async clearPlaybackQueueByTurnId(turnId: string): Promise<void> {
    try {
      await ExpoPlayAudioStreamModule.clearPlaybackQueueByTurnId(turnId);
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to clear playback queue: ${error}`);
    }
  }

  /**
   * Plays a sound.
   * @param {string} audio - The audio to play.
   * @param {string} turnId - The turn ID.
   * @param {string} [encoding] - The encoding format of the audio data ('pcm_f32le' or 'pcm_s16le').
   * @returns {Promise<void>}
   * @throws {Error} If the sound fails to play.
   */
  static async playSound(
    audio: string,
    turnId: string,
    encoding?: Encoding
  ): Promise<void> {
    try {
      await ExpoPlayAudioStreamModule.playSound(
        audio,
        turnId,
        encoding ?? EncodingTypes.PCM_S16LE
      );
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to enqueue audio: ${error}`);
    }
  }

  /**
   * Stops the currently playing sound.
   * @returns {Promise<void>}
   * @throws {Error} If the sound fails to stop.
   */
  static async stopSound(): Promise<void> {
    try {
      await ExpoPlayAudioStreamModule.stopSound();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stop enqueued audio: ${error}`);
    }
  }

  /**
   * Interrupts the current sound.
   * @returns {Promise<void>}
   * @throws {Error} If the sound fails to interrupt.
   */
  static async interruptSound(): Promise<void> {
    try {
      await ExpoPlayAudioStreamModule.interruptSound();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stop enqueued audio: ${error}`);
    }
  }

  /**
   * Resumes the current sound.
   * @returns {Promise<void>}
   * @throws {Error} If the sound fails to resume.
   */
  static resumeSound(): void {
    try {
      ExpoPlayAudioStreamModule.resumeSound();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to resume sound: ${error}`);
    }
  }

  /**
   * Clears the sound queue by turn ID.
   * @param {string} turnId - The turn ID.
   * @returns {Promise<void>}
   * @throws {Error} If the sound queue fails to clear.
   */
  static async clearSoundQueueByTurnId(turnId: string): Promise<void> {
    try {
      await ExpoPlayAudioStreamModule.clearSoundQueueByTurnId(turnId);
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to clear sound queue: ${error}`);
    }
  }

  /**
   * Starts microphone streaming.
   * @param {RecordingConfig} recordingConfig - The recording configuration.
   * @returns {Promise<{recordingResult: StartRecordingResult, subscription: Subscription}>} A promise that resolves to an object containing the recording result and a subscription to audio events.
   * @throws {Error} If the recording fails to start.
   */
  static async startMicrophone(recordingConfig: RecordingConfig): Promise<{
    recordingResult: StartRecordingResult;
    subscription?: Subscription;
  }> {
    let subscription: Subscription | undefined;
    try {
      const { onAudioStream, ...options } = recordingConfig;

      if (onAudioStream && typeof onAudioStream == "function") {
        subscription = addAudioEventListener(
          async (event: AudioEventPayload) => {
            const {
              fileUri,
              deltaSize,
              totalSize,
              position,
              encoded,
              soundLevel,
            } = event;
            if (!encoded) {
              console.error(
                `[ExpoPlayAudioStream] Encoded audio data is missing`
              );
              throw new Error("Encoded audio data is missing");
            }
            onAudioStream?.({
              data: encoded,
              position,
              fileUri,
              eventDataSize: deltaSize,
              totalSize,
              soundLevel,
            });
          }
        );
      }

      const result = await ExpoPlayAudioStreamModule.startMicrophone(options);

      return { recordingResult: result, subscription };
    } catch (error) {
      console.error(error);
      subscription?.remove();
      throw new Error(`Failed to start recording: ${error}`);
    }
  }

  /**
   * Stops the current microphone streaming.
   * @returns {Promise<void>}
   * @throws {Error} If the microphone streaming fails to stop.
   */
  static async stopMicrophone(): Promise<AudioRecording | null> {
    try {
      return await ExpoPlayAudioStreamModule.stopMicrophone();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stop mic stream: ${error}`);
    }
  }

  /**
   * Subscribes to audio events emitted during recording/streaming.
   * @param onMicrophoneStream - Callback function that will be called when audio data is received.
   * The callback receives an AudioDataEvent containing:
   * - data: Base64 encoded audio data at original sample rate
   * - data16kHz: Optional base64 encoded audio data resampled to 16kHz
   * - position: Current position in the audio stream
   * - fileUri: URI of the recording file
   * - eventDataSize: Size of the current audio data chunk
   * - totalSize: Total size of recorded audio so far
   * @returns {Subscription} A subscription object that can be used to unsubscribe from the events
   * @throws {Error} If encoded audio data is missing from the event
   */
  static subscribeToAudioEvents(
    onMicrophoneStream: (event: AudioDataEvent) => Promise<void>
  ): Subscription {
    return addAudioEventListener(async (event: AudioEventPayload) => {
      const { fileUri, deltaSize, totalSize, position, encoded, soundLevel } =
        event;
      if (!encoded) {
        console.error(`[ExpoPlayAudioStream] Encoded audio data is missing`);
        throw new Error("Encoded audio data is missing");
      }
      onMicrophoneStream?.({
        data: encoded,
        position,
        fileUri,
        eventDataSize: deltaSize,
        totalSize,
        soundLevel,
      });
    });
  }

  /**
   * Subscribes to events emitted when a sound chunk has finished playing.
   * @param onSoundChunkPlayed - Callback function that will be called when a sound chunk is played.
   * The callback receives a SoundChunkPlayedEventPayload indicating if this was the final chunk.
   * @returns {Subscription} A subscription object that can be used to unsubscribe from the events.
   */
  static subscribeToSoundChunkPlayed(
    onSoundChunkPlayed: (event: SoundChunkPlayedEventPayload) => Promise<void>
  ): Subscription {
    return addSoundChunkPlayedListener(onSoundChunkPlayed);
  }

  /**
   * Subscribes to events emitted by the audio stream module, for advanced use cases.
   * @param eventName - The name of the event to subscribe to.
   * @param onEvent - Callback function that will be called when the event is emitted.
   * @returns {Subscription} A subscription object that can be used to unsubscribe from the events.
   */
  static subscribe<T extends unknown>(
    eventName: string,
    onEvent: (event: T | undefined) => Promise<void>
  ): Subscription {
    return subscribeToEvent(eventName, onEvent);
  }

  /**
   * Plays a WAV audio file from base64 encoded data.
   * Unlike playSound(), this method plays the audio directly without queueing.
   * @param {string} wavBase64 - Base64 encoded WAV audio data.
   * @returns {Promise<void>}
   * @throws {Error} If the WAV audio fails to play.
   */
  static async playWav(wavBase64: string) {
    try {
      await ExpoPlayAudioStreamModule.playWav(wavBase64);
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to play wav: ${error}`);
    }
  }

  /**
   * Sets the sound player configuration.
   * @param {SoundConfig} config - Configuration options for the sound player.
   * @returns {Promise<void>}
   * @throws {Error} If the configuration fails to update.
   */
  static async setSoundConfig(config: SoundConfig): Promise<void> {
    try {
      await ExpoPlayAudioStreamModule.setSoundConfig(config);
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to set sound configuration: ${error}`);
    }
  }

  /**
   * Prompts the user to select the microphone mode.
   * @returns {Promise<void>}
   * @throws {Error} If the microphone mode fails to prompt.
   */
  static promptMicrophoneModes() {
    ExpoPlayAudioStreamModule.promptMicrophoneModes();
  }

  /**
   * Toggles the silence state of the microphone.
   * @returns {Promise<void>}
   * @throws {Error} If the microphone fails to toggle silence.
   */
  static toggleSilence() {
    ExpoPlayAudioStreamModule.toggleSilence();
  }

}

export {
  AudioDataEvent,
  SoundChunkPlayedEventPayload,
  DeviceReconnectedReason,
  DeviceReconnectedEventPayload,
  AudioRecording,
  RecordingConfig,
  StartRecordingResult,
  AudioEvents,
  SuspendSoundEventTurnId,
  SoundConfig,
  PlaybackMode,
  Encoding,
  EncodingTypes,
  PlaybackModes,
};
