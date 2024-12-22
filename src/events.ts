// packages/expo-audio-stream/src/events.ts

import { EventEmitter, type Subscription } from 'expo-modules-core'


import ExpoPlayAudioStreamModule from './ExpoPlayAudioStreamModule'


const emitter = new EventEmitter(ExpoPlayAudioStreamModule)

export interface AudioEventPayload {
    encoded?: string
    encoded16kHz?: string
    buffer?: Float32Array
    fileUri: string
    lastEmittedSize: number
    position: number
    deltaSize: number
    totalSize: number
    mimeType: string
    streamUuid: string
}

export function addAudioEventListener(
    listener: (event: AudioEventPayload) => Promise<void>
): Subscription {
    return emitter.addListener<AudioEventPayload>('AudioData', listener)
}