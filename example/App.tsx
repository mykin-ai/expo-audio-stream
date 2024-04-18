import { StyleSheet, Text, View } from "react-native";
import { ExpoAudioStream } from "@mykin-ai/expo-audio-stream";
import { useEffect } from "react";
import { sampleA } from "./samples/sample-a";
import { sampleB } from "./samples/sample-b";

export default function App() {
  useEffect(() => {
    async function run() {
      try {
        await ExpoAudioStream.setVolume(100);
        await ExpoAudioStream.streamRiff16Khz16BitMonoPcmChunk(sampleA);
        console.log("streamed A");
        await ExpoAudioStream.streamRiff16Khz16BitMonoPcmChunk(sampleB);
        console.log("streamed B");
        console.log("streaming A & B");
        ExpoAudioStream.streamRiff16Khz16BitMonoPcmChunk(sampleA);
        ExpoAudioStream.streamRiff16Khz16BitMonoPcmChunk(sampleB);
      } catch (error) {
        console.error(error);
      }
    }
    run();
  }, []);

  return (
    <View style={styles.container}>
      <Text>hi</Text>
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
