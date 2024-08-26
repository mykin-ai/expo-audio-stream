import ExpoPlayAudioStreamModule from "./ExpoPlayAudioStreamModule";

export class ExpoPlayAudioStream {
  static async streamRiff16Khz16BitMonoPcmChunk(
    base64Chunk: string
  ): Promise<void> {
    try {
      return ExpoPlayAudioStreamModule.streamRiff16Khz16BitMonoPcmChunk(
        base64Chunk
      );
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stream audio chunk: ${error}`);
    }
  }

  static async setVolume(volme: number): Promise<void> {
    try {
      return await ExpoPlayAudioStreamModule.setVolume(volme);
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to set volume: ${error}`);
    }
  }

  static async pause(): Promise<void> {
    try {
      return await ExpoPlayAudioStreamModule.pause();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to pause audio: ${error}`);
    }
  }

  static async start(): Promise<void> {
    try {
      return await ExpoPlayAudioStreamModule.start();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to start audio: ${error}`);
    }
  }

  static async stop(): Promise<void> {
    try {
      return await ExpoPlayAudioStreamModule.stop();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stop audio: ${error}`);
    }
  }
}
