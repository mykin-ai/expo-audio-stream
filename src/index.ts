import { Subscription } from "expo-modules-core";
import ExpoPlayAudioStreamModule from "./ExpoPlayAudioStreamModule";
import { AudioRecording, RecordingConfig, StartRecordingResult } from "./types";

import { addAudioEventListener, AudioEventPayload } from "./events";

export class ExpoPlayAudioStream {

  /**
   * Starts microphone recording.
   * @param {RecordingConfig} recordingConfig - Configuration for the recording.
   * @returns {Promise<{recordingResult: StartRecordingResult, subscription: Subscription}>} A promise that resolves to an object containing the recording result and a subscription to audio events.
   * @throws {Error} If the recording fails to start.
   */
  static async startRecording(
    recordingConfig: RecordingConfig
  ): Promise<{
    recordingResult: StartRecordingResult;
    subscription: Subscription;
  }> {
    try {
      const { onAudioStream, ...options } = recordingConfig;

      const subscription = addAudioEventListener(
        async (event: AudioEventPayload) => {
          const { fileUri, deltaSize, totalSize, position, encoded } = event;
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
          });
        }
      );

      const recordingResult = await ExpoPlayAudioStreamModule.startRecording(
        options
      );
      return { recordingResult, subscription };
    } catch (error) {
      console.error(error);
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
  static async playAudio(
    base64Chunk: string,
    turnId: string
  ): Promise<void> {
    try {
      return ExpoPlayAudioStreamModule.playAudio(
        base64Chunk,
        turnId
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
      return await ExpoPlayAudioStreamModule.pause();
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
      return await ExpoPlayAudioStreamModule.stop();
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
      return await ExpoPlayAudioStreamModule.clearPlaybackQueueByTurnId(turnId);
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to clear playback queue: ${error}`);
    }
  }
}
