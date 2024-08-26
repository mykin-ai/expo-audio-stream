# Expo Play Audio Stream 🎶

The Expo Play Audio Stream module is a powerful tool for streaming audio data in your Expo-based React Native applications. It provides a seamless way to play audio chunks in real-time, allowing you to build audio-centric features like voice assistants, audio players, and more.

## Motivation 🎯

Expo's built-in audio capabilities are limited to playing pre-loaded audio files. The Expo Audio Stream module was created to address this limitation, enabling developers to stream audio data dynamically and have more control over the audio playback process.

## Example Usage 🚀

Here's an example of how you can use the Expo Audio Stream module to play a sequence of audio chunks:

```javascript
import { ExpoPlayAudioStream } from 'expo-audio-stream';

// Assuming you have some audio data in base64 format
const sampleA = 'base64EncodedAudioDataA';
const sampleB = 'base64EncodedAudioDataB';

useEffect(() => {
  async function playAudioChunks() {
    try {
      await ExpoPlayAudioStream.setVolume(100);
      await ExpoPlayAudioStream.streamRiff16Khz16BitMonoPcmChunk(sampleA);
      console.log('Streamed A');
      await ExpoPlayAudioStream.streamRiff16Khz16BitMonoPcmChunk(sampleB);
      console.log('Streamed B');
      console.log('Streaming A & B');
      ExpoPlayAudioStream.streamRiff16Khz16BitMonoPcmChunk(sampleA);  
      ExpoPlayAudioStream.streamRiff16Khz16BitMonoPcmChunk(sampleB);
    } catch (error) {
      console.error(error);
    }
  }

  playAudioChunks();
}, []);
```

## API 📚

The Expo Play Audio Stream module provides the following API:

- `streamRiff16Khz16BitMonoPcmChunk(base64Chunk: string): Promise<void>`: Streams a base64-encoded audio chunk in the RIFF format with 16 kHz, 16-bit, mono PCM encoding.
- `setVolume(volume: number): Promise<void>`: Sets the volume of the audio playback, where `volume` is a value between 0 and 100.
- `pause(): Promise<void>`: Pauses the audio playback.
- `start(): Promise<void>`: Starts the audio playback.
- `stop(): Promise<void>`: Stops the audio playback and clears any remaining audio data.

## Swift Implementation 🍎

The Swift implementation of the Expo Audio Stream module uses the `AVFoundation` framework to handle audio playback. It utilizes a dual-buffer queue system to ensure smooth and uninterrupted audio streaming. The module also configures the audio session and manages the audio engine and player node.

## Kotlin Implementation 🤖

The Kotlin implementation of the Expo Audio Stream module uses the `AudioTrack` class from the Android framework to handle audio playback. It uses a concurrent queue to manage the audio chunks and a coroutine-based playback loop to ensure efficient and asynchronous processing of the audio data.

## Limitations and Considerations ⚠️

- The Expo Play Audio Stream module is designed to work with specific audio formats (RIFF, 16 kHz, 16-bit, mono PCM). If your audio data is in a different format, you may need to convert it before using the module.
- The module does not provide advanced features like audio effects, mixing, or recording. It is primarily focused on real-time audio streaming.
- The performance of the module may depend on the device's hardware capabilities and the complexity of the audio data being streamed.

## Contributions 🤝

Contributions to the Expo Audio Stream module are welcome! If you encounter any issues or have ideas for improvements, feel free to open an issue or submit a pull request on the [GitHub repository](https://github.com/expo/expo-audio-stream).

## License 📄

The Expo Play Audio Stream module is licensed under the [MIT License](LICENSE).
