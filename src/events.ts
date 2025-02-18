// packages/expo-audio-stream/src/events.ts

import { EventEmitter, type Subscription } from 'expo-modules-core'


import ExpoPlayAudioStreamModule from './ExpoPlayAudioStreamModule'


const emitter = new EventEmitter(ExpoPlayAudioStreamModule)

emitter.addListener('SoundChunkPlayed', (event: SoundChunkPlayedEventPayload) => {
})

export interface AudioEventPayload {
    encoded?: string
    buffer?: Float32Array
    fileUri: string
    lastEmittedSize: number
    position: number
    deltaSize: number
    totalSize: number
    mimeType: string
    streamUuid: string
}

export type SoundChunkPlayedEventPayload = {
    isFinal: boolean
}

export const AudioEvents = {
    AudioData: 'AudioData',
    SoundChunkPlayed: 'SoundChunkPlayed',
    SoundStarted: 'SoundStarted',
}

export function addAudioEventListener(
    listener: (event: AudioEventPayload) => Promise<void>
): Subscription {
    return emitter.addListener<AudioEventPayload>('AudioData', listener)
}

export function addSoundChunkPlayedListener(
    listener: (event: SoundChunkPlayedEventPayload) => Promise<void>
): Subscription {
    return emitter.addListener<SoundChunkPlayedEventPayload>('SoundChunkPlayed', listener)
}

export function subscribeToEvent<T extends unknown>(
    eventName: string,
    listener: (event: T | undefined) => Promise<void>
): Subscription {
    return emitter.addListener(eventName, listener)
}

