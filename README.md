# Expo Play Audio Stream 🎶

The Expo Play Audio Stream module is a powerful tool for recording and streaming audio data in your Expo-based React Native applications. It provides a seamless way to record audio from the microphone and play audio chunks in real-time, allowing you to build audio-centric features like voice assistants, audio players, voice recorders, and more.

## Motivation 🎯

Expo's built-in audio capabilities are limited to playing pre-loaded audio files and basic recording. The Expo Audio Stream module was created to address these limitations, enabling developers to record high-quality audio with real-time streaming capabilities and have more control over both the recording and playback process. The module provides features like dual-stream output (original and 16kHz versions) which is particularly useful for voice activity detection and speech recognition applications.

## Example Usage 🚀

Here's how you can use the Expo Play Audio Stream module for different scenarios:

### Standard Recording and Playback

```javascript
import { ExpoPlayAudioStream } from 'expo-audio-stream';

// Example of standard recording and playback
async function handleStandardRecording() {
  try {
    // Set volume for playback
    await ExpoPlayAudioStream.setVolume(0.8);

    // Start recording with configuration
    const { recordingResult, subscription } = await ExpoPlayAudioStream.startRecording({
      onAudioStream: (event) => {
        console.log('Received audio stream:', {
          audioDataBase64: event.data,
          audioData16kHzBase64: event.data16kHz, // usually used for voice activity detection like silero models
          position: event.position,
          eventDataSize: event.eventDataSize,
          totalSize: event.totalSize
        });
      }
    });

    // After some time, stop recording
    setTimeout(async () => {
      const recording = await ExpoPlayAudioStream.stopRecording();
      console.log('Recording stopped:', recording);

      // Read the file from the fileUri and convert to base64

      // Play the recorded audio
      const turnId = 'example-turn-1';
      await ExpoPlayAudioStream.playAudio(base64Content, turnId);

      // Clean up
      subscription?.remove();
    }, 5000);

  } catch (error) {
    console.error('Audio handling error:', error);
  }
}

// You can also subscribe to audio events from anywhere
const audioSubscription = ExpoPlayAudioStream.subscribeToAudioEvents(async (event) => {
  console.log('Audio event received:', {
    data: event.data,
    data16kHz: event.data16kHz
  });
});
// Don't forget to clean up when done
// audioSubscription.remove();
```

### Simultaneous Recording and Playback (⚠️ IOS only for now)

```javascript
import { ExpoPlayAudioStream } from 'expo-audio-stream';

// Example of simultaneous recording and playback with voice processing
async function handleSimultaneousRecordAndPlay() {
  try {
    // Start microphone with voice processing
    const { recordingResult, subscription } = await ExpoPlayAudioStream.startMicrophone({
      onAudioStream: (event) => {
        console.log('Received audio stream with voice processing:', {
          audioDataBase64: event.data,
          audioData16kHz: event.data16kHz
        });
      }
    });

    // Play audio while recording is active
    const turnId = 'response-turn-1';
    await ExpoPlayAudioStream.playSound(someAudioBase64, turnId);

    // Example of controlling playback during recording
    setTimeout(async () => {
      // Interrupt current playback
      await ExpoPlayAudioStream.interruptSound();
      
      // Resume playback
      await ExpoPlayAudioStream.resumeSound();

      // Stop microphone recording
      await ExpoPlayAudioStream.stopMicrophone();

      // Clean up
      subscription?.remove();
    }, 5000);

  } catch (error) {
    console.error('Simultaneous audio handling error:', error);
  }
}
```

## API 📚

The Expo Play Audio Stream module provides the following methods:

### Standard Audio Operations

- `startRecording(recordingConfig: RecordingConfig)`: Starts microphone recording with the specified configuration. Returns a promise with recording result and audio event subscription.

- `stopRecording()`: Stops the current microphone recording and returns the audio recording data.

- `playAudio(base64Chunk: string, turnId: string)`: Plays a base64 encoded audio chunk with the specified turn ID.

- `pauseAudio()`: Pauses the current audio playback.

- `stopAudio()`: Stops the currently playing audio.

- `setVolume(volume: number)`: Sets the volume for audio playback (0.0 to 1.0).

- `clearPlaybackQueueByTurnId(turnId: string)`: Clears the playback queue for a specific turn ID.

- `subscribeToAudioEvents(onMicrophoneStream: (event: AudioDataEvent) => Promise<void>)`: Subscribe to recording events from anywhere in your application. Returns a subscription that should be cleaned up when no longer needed.

### Simultaneous Recording and Playback

These methods are specifically designed for scenarios where you need to record and play audio at the same time:

- `startMicrophone(recordingConfig: RecordingConfig)`: Starts microphone streaming with voice processing enabled. Returns a promise with recording result and audio event subscription.

- `stopMicrophone()`: Stops the microphone streaming when in simultaneous mode.

- `playSound(audio: string, turnId: string)`: Plays a sound while recording is active. Uses voice processing to prevent feedback.

- `interruptSound()`: Interrupts the current sound playback in simultaneous mode.

- `resumeSound()`: Resumes the current sound playback in simultaneous mode.

All methods are static and most return Promises that resolve when the operation is complete. Error handling is built into each method, with descriptive error messages if operations fail.

## Swift Implementation 🍎

The Swift implementation of the Expo Audio Stream module uses the `AVFoundation` framework to handle audio playback. It utilizes a dual-buffer queue system to ensure smooth and uninterrupted audio streaming. The module also configures the audio session and manages the audio engine and player node.

## Kotlin Implementation 🤖

The Kotlin implementation of the Expo Audio Stream module uses the `AudioTrack` class from the Android framework to handle audio playback. It uses a concurrent queue to manage the audio chunks and a coroutine-based playback loop to ensure efficient and asynchronous processing of the audio data.

## Voice Processing and Isolation 🎤

The module implements several audio optimizations for voice recording:

- On iOS 15 and later, users are prompted with system voice isolation options (`microphoneModes`), allowing them to choose their preferred voice isolation level.
- When simultaneous recording and playback is enabled, the module uses iOS voice processing which includes:
  - Noise reduction
  - Echo cancellation
  - Voice optimization
  
Note: Voice processing may result in lower audio levels as it optimizes for voice clarity over volume. This is a trade-off made to ensure better voice quality and reduce background noise.

## Limitations and Considerations ⚠️

- The Expo Play Audio Stream module is designed to work with specific audio formats (RIFF, 16 kHz, 16-bit, mono PCM). If your audio data is in a different format, you may need to convert it before using the module.
- The module does not provide advanced features like audio effects or mixing. It is primarily focused on real-time audio streaming and recording.
- The performance of the module may depend on the device's hardware capabilities and the complexity of the audio data being streamed.

## Contributions 🤝

Contributions to the Expo Audio Stream module are welcome! If you encounter any issues or have ideas for improvements, feel free to open an issue or submit a pull request on the [GitHub repository](https://github.com/expo/expo-audio-stream).

## License 📄

The Expo Play Audio Stream module is licensed under the [MIT License](LICENSE).
