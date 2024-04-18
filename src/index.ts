import ExpoAudioStreamModule from "./ExpoAudioStreamModule";

export class ExpoAudioStream {
  static async streamRiff16Khz16BitMonoPcmChunk(
    base64Chunk: string
  ): Promise<void> {
    try {
      return await ExpoAudioStreamModule.streamRiff16Khz16BitMonoPcmChunk(
        base64Chunk
      );
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stream audio chunk: ${error}`);
    }
  }

  static async setVolume(volme: number): Promise<void> {
    try {
      return await ExpoAudioStreamModule.setVolume(volme);
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to set volume: ${error}`);
    }
  }

  static async pause(): Promise<void> {
    try {
      return await ExpoAudioStreamModule.pause();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to pause audio: ${error}`);
    }
  }

  static async start(): Promise<void> {
    try {
      return await ExpoAudioStreamModule.start();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to start audio: ${error}`);
    }
  }

  static async stop(): Promise<void> {
    try {
      return await ExpoAudioStreamModule.stop();
    } catch (error) {
      console.error(error);
      throw new Error(`Failed to stop audio: ${error}`);
    }
  }
}
