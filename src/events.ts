// packages/expo-audio-stream/src/events.ts

import { EventEmitter, type Subscription } from 'expo-modules-core'


import ExpoPlayAudioStreamModule from './ExpoPlayAudioStreamModule'


const emitter = new EventEmitter(ExpoPlayAudioStreamModule)

emitter.addListener('SoundChunkPlayed', (event: SoundChunkPlayedEventPayload) => {})

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
    soundLevel?: number
}

export type SoundChunkPlayedEventPayload = {
    isFinal: boolean
}

export const DeviceReconnectedReasons = {
    newDeviceAvailable: 'newDeviceAvailable',
    oldDeviceUnavailable: 'oldDeviceUnavailable',
    unknown: 'unknown',
} as const

export type DeviceReconnectedReason = (typeof DeviceReconnectedReasons)[keyof typeof DeviceReconnectedReasons]

export type DeviceReconnectedEventPayload = {
    reason: DeviceReconnectedReason
}

export const AudioEvents = {
    AudioData: 'AudioData',
    SoundChunkPlayed: 'SoundChunkPlayed',
    SoundStarted: 'SoundStarted',
    DeviceReconnected: 'DeviceReconnected',
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

