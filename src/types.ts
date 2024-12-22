export type EncodingType = 'pcm_32bit' | 'pcm_16bit' | 'pcm_8bit'
export type SampleRate = 16000 | 44100 | 48000
export type BitDepth = 8 | 16 | 32

export interface StartRecordingResult {
    fileUri: string
    mimeType: string
    channels?: number
    bitDepth?: BitDepth
    sampleRate?: SampleRate
}

export interface AudioDataEvent {
    data: string | Float32Array
    data16kHz?: string | Float32Array
    position: number
    fileUri: string
    eventDataSize: number
    totalSize: number
}


export interface RecordingConfig {
    sampleRate?: SampleRate // Sample rate for recording
    channels?: 1 | 2 // 1 or 2 (MONO or STEREO)
    encoding?: EncodingType // Encoding type for the recording
    interval?: number // Interval in milliseconds at which to emit recording data

    // Optional parameters for audio processing
    enableProcessing?: boolean // Boolean to enable/disable audio processing (default is false)
    pointsPerSecond?: number // Number of data points to extract per second of audio (default is 1000)
    onAudioStream?: (event: AudioDataEvent) => Promise<void> // Callback function to handle audio stream
}

export interface Chunk {
    text: string
    timestamp: [number, number | null]
}

export interface TranscriberData {
    id: string
    isBusy: boolean
    text: string
    startTime: number
    endTime: number
    chunks: Chunk[]
}

export interface AudioRecording {
    fileUri: string
    filename: string
    durationMs: number
    size: number
    channels: number
    bitDepth: BitDepth
    sampleRate: SampleRate
    mimeType: string
    transcripts?: TranscriberData[]
    wavPCMData?: Float32Array // Full PCM data for the recording in WAV format (only on web, for native use the fileUri)
}

