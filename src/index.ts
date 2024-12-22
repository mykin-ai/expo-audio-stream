import { Subscription } from "expo-modules-core";
import ExpoPlayAudioStreamModule from "./ExpoPlayAudioStreamModule";
import {
  AudioDataEvent,
  AudioRecording,
  RecordingConfig,
  StartRecordingResult,
} from "./types";

import { addAudioEventListener, AudioEventPayload } from "./events";

export class ExpoPlayAudioStream {
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
        const {
          fileUri,
          deltaSize,
          totalSize,
          position,
          encoded,
          encoded16kHz,
        } = event;
        if (!encoded) {
          console.error(`[ExpoPlayAudioStream] Encoded audio data is missing`);
          throw new Error("Encoded audio data is missing");
        }
        onAudioStream?.({
          data: encoded,
          data16kHz: encoded16kHz,
          position,
          fileUri,
          eventDataSize: deltaSize,
          totalSize,
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
   * @returns {Promise<void>}
   * @throws {Error} If the audio chunk fails to stream.
   */
  static async playAudio(base64Chunk: string, turnId: string): Promise<void> {
    try {
      return ExpoPlayAudioStreamModule.playAudio(base64Chunk, turnId);
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
   * Sets the volume for the audio playback.
   * @param {number} volume - The volume to set (0.0 to 1.0).
   * @returns {Promise<void>}
   * @throws {Error} If the volume fails to set.
   */
  static async setVolume(volume: number): Promise<void> {
    try {
      return await ExpoPlayAudioStreamModule.setVolume(volume);
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to set volume: ${error}`);
    }
  }

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
   * @returns {Promise<void>}
   * @throws {Error} If the sound fails to play.
   */
  static async playSound(audio: string, turnId: string): Promise<void> {
    try {
      await ExpoPlayAudioStreamModule.playSound(audio, turnId);
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to enqueue audio: ${error}`);
    }
  }

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
              encoded16kHz,
            } = event;
            if (!encoded) {
              console.error(
                `[ExpoPlayAudioStream] Encoded audio data is missing`
              );
              throw new Error("Encoded audio data is missing");
            }
            onAudioStream?.({
              data: encoded,
              data16kHz: encoded16kHz,
              position,
              fileUri,
              eventDataSize: deltaSize,
              totalSize,
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
  static async stopMicrophone(): Promise<void> {
    try {
      return await ExpoPlayAudioStreamModule.stopMicrophone();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stop mic stream: ${error}`);
    }
  }

  static subscribeToAudioEvents(
    onMicrophoneStream: (event: AudioDataEvent) => Promise<void>
  ): Subscription {
    return addAudioEventListener(async (event: AudioEventPayload) => {
      const { fileUri, deltaSize, totalSize, position, encoded, encoded16kHz } =
        event;
      if (!encoded) {
        console.error(`[ExpoPlayAudioStream] Encoded audio data is missing`);
        throw new Error("Encoded audio data is missing");
      }
      onMicrophoneStream?.({
        data: encoded,
        data16kHz: encoded16kHz,
        position,
        fileUri,
        eventDataSize: deltaSize,
        totalSize,
      });
    });
  }
}

export {
  AudioDataEvent,
  AudioRecording,
  RecordingConfig,
  StartRecordingResult,
};
