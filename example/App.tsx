import { Button, Platform, StyleSheet, Text, View } from "react-native";
import { ExpoPlayAudioStream } from "@mykin-ai/expo-audio-stream";
import { useEffect, useRef } from "react";
import { sampleA } from "./samples/sample-a";
import { sampleB } from "./samples/sample-b";
import { sampleC } from "./samples/sample-c";
import {
  AudioDataEvent,
  EncodingTypes,
} from "@mykin-ai/expo-audio-stream/types";
import type { EventSubscription } from "expo-modules-core";

const ANDROID_SAMPLE_RATE = 16000;
const IOS_SAMPLE_RATE = 48000;
const CHANNELS = 1;
const ENCODING = "pcm_16bit";
const RECORDING_INTERVAL = 100;

// Sample audio files are encoded at 16kHz
const SAMPLE_PLAYBACK_RATE = 16000;

const turnId1 = "turnId1";
const turnId2 = "turnId2";

export default function App() {
  const eventListenerSubscriptionRef = useRef<EventSubscription | undefined>(
    undefined
  );

  const onAudioCallback = async (audio: AudioDataEvent) => {
    console.log(audio.data.slice(0, 100));
  };

  const playEventsListenerSubscriptionRef = useRef<
    EventSubscription | undefined
  >(undefined);

  useEffect(() => {
    playEventsListenerSubscriptionRef.current =
      ExpoPlayAudioStream.subscribeToSoundChunkPlayed(async (event) => {
        console.log(event);
      });

    return () => {
      if (playEventsListenerSubscriptionRef.current) {
        playEventsListenerSubscriptionRef.current.remove();
        playEventsListenerSubscriptionRef.current = undefined;
      }
    };
  }, []);

  return (
    <View style={styles.container}>
      <Text>hi</Text>
      <Button
        onPress={async () => {
          // Set sample rate to match the audio file (16kHz)
          await ExpoPlayAudioStream.setSoundConfig({
            sampleRate: SAMPLE_PLAYBACK_RATE,
            playbackMode: "regular",
          });
          await ExpoPlayAudioStream.playSound(sampleB, turnId1);
        }}
        title="Play sample B"
      />
      <View style={{ height: 10, marginBottom: 10 }}>
        <Text>====================</Text>
      </View>
      <Button
        onPress={async () => {
          await ExpoPlayAudioStream.pauseAudio();
        }}
        title="Pause Audio"
      />
      <View style={{ height: 10, marginBottom: 10 }}>
        <Text>====================</Text>
      </View>
      <Button
        onPress={async () => {
          // Set sample rate to match the audio file (16kHz)
          await ExpoPlayAudioStream.setSoundConfig({
            sampleRate: SAMPLE_PLAYBACK_RATE,
            playbackMode: "regular",
          });
          await ExpoPlayAudioStream.playSound(sampleA, turnId2);
        }}
        title="Play sample A"
      />
      <View style={{ height: 10, marginBottom: 10 }}>
        <Text>====================</Text>
      </View>
      <Button
        onPress={async () => {
          await ExpoPlayAudioStream.playWav(sampleC);
        }}
        title="Play WAV fragment"
      />
      <View style={{ height: 10, marginBottom: 10 }}>
        <Text>====================</Text>
      </View>
      <Button
        onPress={async () => {
          if (!(await isMicrophonePermissionGranted())) {
            const permissionGranted = await requestMicrophonePermission();
            if (!permissionGranted) {
              return;
            }
          }
          const sampleRate =
            Platform.OS === "ios" ? IOS_SAMPLE_RATE : ANDROID_SAMPLE_RATE;
          const { recordingResult, subscription } =
            await ExpoPlayAudioStream.startMicrophone({
              interval: RECORDING_INTERVAL,
              sampleRate,
              channels: CHANNELS,
              encoding: ENCODING,
              onAudioStream: onAudioCallback,
            });
          console.log(JSON.stringify(recordingResult, null, 2));
          eventListenerSubscriptionRef.current = subscription;
        }}
        title="Start Recording"
      />
      <View style={{ height: 10, marginBottom: 10 }}>
        <Text>====================</Text>
      </View>
      <Button
        onPress={async () => {
          await ExpoPlayAudioStream.stopMicrophone();
          if (eventListenerSubscriptionRef.current) {
            eventListenerSubscriptionRef.current.remove();
            eventListenerSubscriptionRef.current = undefined;
          }
        }}
        title="Stop Recording"
      />
      <View style={{ height: 10, marginBottom: 10 }}>
        <Text>====================</Text>
      </View>
      <Button
        onPress={async () => {
          await ExpoPlayAudioStream.clearPlaybackQueueByTurnId(turnId1);
        }}
        title="Clear turnId1"
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#fff",
    alignItems: "center",
    justifyContent: "center",
  },
});

export const requestMicrophonePermission = async (): Promise<boolean> => {
  const result = await ExpoPlayAudioStream.requestPermissionsAsync();
  return result.granted;
};

export const isMicrophonePermissionGranted = async (): Promise<boolean> => {
  const result = await ExpoPlayAudioStream.getPermissionsAsync();
  return result.granted;
};
