export type RecordingEncodingType = 'pcm_32bit' | 'pcm_16bit' | 'pcm_8bit'
export type SampleRate = 16000 | 44100 | 48000
export type BitDepth = 8 | 16 | 32

export const PlaybackModes = {
  REGULAR: 'regular',
  VOICE_PROCESSING: 'voiceProcessing',
  CONVERSATION: 'conversation',
} as const
/**
 * Defines different playback modes for audio processing
 */
export type PlaybackMode = (typeof PlaybackModes)[keyof typeof PlaybackModes]

/**
 * Configuration for audio playback settings
 */
export interface SoundConfig {
  /**
   * The sample rate for audio playback in Hz
   */
  sampleRate?: SampleRate
  
  /**
   * The playback mode (regular, voiceProcessing, or conversation)
   */
  playbackMode?: PlaybackMode
  
  /**
   * When true, resets to default configuration regardless of other parameters
   */
  useDefault?: boolean
}

export const EncodingTypes = {
  PCM_F32LE: 'pcm_f32le',
  PCM_S16LE: 'pcm_s16le',
} as const

/**
 * Defines different encoding formats for audio data
 */
export type Encoding = (typeof EncodingTypes)[keyof typeof EncodingTypes]

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
    soundLevel?: number
}


export interface RecordingConfig {
    sampleRate?: SampleRate // Sample rate for recording
    channels?: 1 | 2 // 1 or 2 (MONO or STEREO)
    encoding?: RecordingEncodingType // Encoding type for the recording
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

