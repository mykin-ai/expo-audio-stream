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
  });
});
// Don't forget to clean up when done
// audioSubscription.remove();
```

### Simultaneous Recording and Playback (⚠️ iOS only)

These methods are specifically designed for scenarios where you need to record and play audio at the same time. Currently only available on iOS:

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
        });
      }
    });

    // Play audio while recording is active
    const turnId = 'response-turn-1';
    await ExpoPlayAudioStream.playSound(someAudioBase64, turnId);

    // Play a complete WAV file directly
    await ExpoPlayAudioStream.playWav(wavBase64Data);

    // Example of controlling playback during recording
    setTimeout(async () => {
      // Clear the queue for a specific turn
      await ExpoPlayAudioStream.clearSoundQueueByTurnId(turnId);

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

- `destroy()`: Destroys the audio stream module, cleaning up all resources. This should be called when the module is no longer needed. It will reset all internal state and release audio resources.

- `startRecording(recordingConfig: RecordingConfig)`: Starts microphone recording with the specified configuration. Returns a promise with recording result and audio event subscription. Throws an error if the recording fails to start.

- `stopRecording()`: Stops the current microphone recording. Returns a promise that resolves to the audio recording data. Throws an error if the recording fails to stop.

- `playAudio(base64Chunk: string, turnId: string)`: Plays a base64 encoded audio chunk with the specified turn ID. Throws an error if the audio chunk fails to stream.

- `pauseAudio()`: Pauses the current audio playback. Throws an error if the audio playback fails to pause.

- `stopAudio()`: Stops the currently playing audio. Throws an error if the audio fails to stop.

- `clearPlaybackQueueByTurnId(turnId: string)`: Clears the playback queue for a specific turn ID. Throws an error if the playback queue fails to clear.

### Simultaneous Recording and Playback

- `startMicrophone(recordingConfig: RecordingConfig)`: Starts microphone streaming. Returns a promise that resolves to an object containing the recording result and a subscription to audio events. Throws an error if the recording fails to start.

- `stopMicrophone()`: Stops the current microphone streaming. Returns a promise that resolves to the audio recording data or null. Throws an error if the microphone streaming fails to stop.

- `playSound(audio: string, turnId: string)`: Plays a sound. Throws an error if the sound fails to play.

- `stopSound()`: Stops the currently playing sound. Throws an error if the sound fails to stop.

- `interruptSound()`: Interrupts the current sound. Throws an error if the sound fails to interrupt.

- `resumeSound()`: Resumes the current sound. Throws an error if the sound fails to resume.

- `clearSoundQueueByTurnId(turnId: string)`: Clears the sound queue for a specific turn ID. Throws an error if the sound queue fails to clear.

- `playWav(wavBase64: string)`: Plays a WAV format audio file from base64 encoded data. Unlike playSound(), this method plays the audio directly without queueing. Throws an error if the WAV audio fails to play.

### Event Subscriptions

- `subscribeToAudioEvents(onMicrophoneStream: (event: AudioDataEvent) => Promise<void>)`: Subscribes to audio events emitted during recording/streaming. The callback receives an AudioDataEvent containing:
  - `data`: Base64 encoded audio data at original sample rate
  - `position`: Current position in the audio stream
  - `fileUri`: URI of the recording file
  - `eventDataSize`: Size of the current audio data chunk
  - `totalSize`: Total size of recorded audio so far
  Returns a subscription that should be cleaned up when no longer needed.

- `subscribeToSoundChunkPlayed(onSoundChunkPlayed: (event: SoundChunkPlayedEventPayload) => Promise<void>)`: Subscribes to events emitted when a sound chunk has finished playing. The callback receives a payload indicating if this was the final chunk. Returns a subscription that should be cleaned up when no longer needed.

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
