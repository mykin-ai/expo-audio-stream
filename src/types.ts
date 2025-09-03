export type RecordingEncodingType =
  | 'pcm_32bit'
  | 'pcm_16bit'
  | 'pcm_8bit';
export type SampleRate = 16000 | 44100 | 48000;
export type BitDepth = 8 | 16 | 32;

export const PlaybackModes = {
  REGULAR: 'regular',
  VOICE_PROCESSING: 'voiceProcessing',
  CONVERSATION: 'conversation',
} as const;
/**
 * Defines different playback modes for audio processing
 */
export type PlaybackMode =
  (typeof PlaybackModes)[keyof typeof PlaybackModes];

/**
 * Configuration for audio playback settings
 */
export interface SoundConfig {
  /**
   * The sample rate for audio playback in Hz
   */
  sampleRate?: SampleRate;

  /**
   * The playback mode (regular, voiceProcessing, or conversation)
   */
  playbackMode?: PlaybackMode;

  /**
   * When true, resets to default configuration regardless of other parameters
   */
  useDefault?: boolean;

  /**
   * Enable jitter buffering for audio streams
   */
  enableBuffering?: boolean;

  /**
   * Automatically enable buffering based on network conditions
   */
  autoBuffer?: boolean;

  /**
   * Configuration for the jitter buffer when enableBuffering is true
   */
  bufferConfig?: Partial<IAudioBufferConfig>;
}

/**
 * Configuration for buffered audio streaming
 */
export interface BufferedStreamConfig {
  /**
   * Turn ID for queue management
   */
  turnId: string;

  /**
   * Audio encoding format
   */
  encoding?: Encoding;

  /**
   * Buffer configuration options
   */
  bufferConfig?: Partial<IAudioBufferConfig>;

  /**
   * Callback for buffer health updates
   */
  onBufferHealth?: (metrics: IBufferHealthMetrics) => void;
}

export const EncodingTypes = {
  PCM_F32LE: 'pcm_f32le',
  PCM_S16LE: 'pcm_s16le',
} as const;

/**
 * Defines different encoding formats for audio data
 */
export type Encoding =
  (typeof EncodingTypes)[keyof typeof EncodingTypes];

/**
 * Smart buffering mode options
 */
export type SmartBufferMode =
  | 'conservative'
  | 'balanced'
  | 'aggressive'
  | 'adaptive';

/**
 * Network condition indicators for smart buffering
 */
export interface NetworkConditions {
  latency?: number; // Round-trip time in ms
  jitter?: number; // Network jitter in ms
  packetLoss?: number; // Packet loss percentage (0-100)
  bandwidth?: number; // Available bandwidth estimate
}

/**
 * Smart buffering configuration
 */
export interface SmartBufferConfig {
  mode: SmartBufferMode;
  networkConditions?: NetworkConditions;
  adaptiveThresholds?: {
    highLatencyMs?: number; // Threshold to enable aggressive buffering
    highJitterMs?: number; // Threshold to increase buffer size
    packetLossPercent?: number; // Threshold to enable buffering
  };
}

export interface StartRecordingResult {
  fileUri: string;
  mimeType: string;
  channels?: number;
  bitDepth?: BitDepth;
  sampleRate?: SampleRate;
}

export interface AudioDataEvent {
  data: string | Float32Array;
  data16kHz?: string | Float32Array;
  position: number;
  fileUri: string;
  eventDataSize: number;
  totalSize: number;
  soundLevel?: number;
}

export interface RecordingConfig {
  sampleRate?: SampleRate; // Sample rate for recording
  channels?: 1 | 2; // 1 or 2 (MONO or STEREO)
  encoding?: RecordingEncodingType; // Encoding type for the recording
  interval?: number; // Interval in milliseconds at which to emit recording data

  // Optional parameters for audio processing
  enableProcessing?: boolean; // Boolean to enable/disable audio processing (default is false)
  pointsPerSecond?: number; // Number of data points to extract per second of audio (default is 1000)
  onAudioStream?: (event: AudioDataEvent) => Promise<void>; // Callback function to handle audio stream
}

export interface Chunk {
  text: string;
  timestamp: [number, number | null];
}

export interface TranscriberData {
  id: string;
  isBusy: boolean;
  text: string;
  startTime: number;
  endTime: number;
  chunks: Chunk[];
}

export interface AudioRecording {
  fileUri: string;
  filename: string;
  durationMs: number;
  size: number;
  channels: number;
  bitDepth: BitDepth;
  sampleRate: SampleRate;
  mimeType: string;
  transcripts?: TranscriberData[];
  wavPCMData?: Float32Array; // Full PCM data for the recording in WAV format (only on web, for native use the fileUri)
}

// Audio Jitter Buffer Types

/**
 * Configuration for audio buffer management
 */
export interface IAudioBufferConfig {
  targetBufferMs: number; // Target buffer size in milliseconds
  minBufferMs: number; // Minimum buffer size before underrun handling
  maxBufferMs: number; // Maximum buffer size before overrun handling
  frameIntervalMs: number; // Expected frame interval in milliseconds
}

/**
 * Audio payload for playback containing base64 encoded audio data
 */
export interface IAudioPlayPayload {
  audioData: string; // Base64 encoded PCM audio data
  isFirst?: boolean; // True if this is the first chunk in a stream
  isFinal?: boolean; // True if this is the final chunk in a stream
}

/**
 * Processed audio frame with metadata
 */
export interface IAudioFrame {
  sequenceNumber: number; // Sequential frame number
  data: IAudioPlayPayload; // Original audio payload
  duration: number; // Estimated frame duration in milliseconds
  timestamp: number; // Frame timestamp when processed
}

/**
 * Buffer health states for quality monitoring
 */
export type BufferHealthState =
  | 'idle'
  | 'healthy'
  | 'degraded'
  | 'critical';

/**
 * Comprehensive buffer health and quality metrics
 */
export interface IBufferHealthMetrics {
  currentBufferMs: number; // Current buffer level in milliseconds
  targetBufferMs: number; // Target buffer level in milliseconds
  underrunCount: number; // Total number of buffer underruns
  overrunCount: number; // Total number of buffer overruns
  averageJitter: number; // Average network jitter in milliseconds
  bufferHealthState: BufferHealthState; // Current buffer health assessment
  adaptiveAdjustmentsCount: number; // Number of adaptive adjustments made
}

/**
 * Interface for audio buffer management
 */
export interface IAudioBufferManager {
  enqueueFrames(audioData: IAudioPlayPayload): void;
  startPlayback(): void;
  stopPlayback(): void;
  isPlaying(): boolean;
  getHealthMetrics(): IBufferHealthMetrics;
  updateConfig(config: Partial<IAudioBufferConfig>): void;
  applyAdaptiveAdjustments(): void;
  destroy(): void;
  getCurrentBufferMs(): number;
}

/**
 * Interface for frame processing
 */
export interface IFrameProcessor {
  parseChunk(payload: IAudioPlayPayload): IAudioFrame[];
  reset(): void;
}

/**
 * Interface for quality monitoring
 */
export interface IQualityMonitor {
  recordFrameArrival(timestamp: number): void;
  recordUnderrun(): void;
  recordOverrun(): void;
  updateBufferLevel(bufferMs: number): void;
  getMetrics(): IBufferHealthMetrics;
  getBufferHealthState(
    isPlaying: boolean,
    currentLatencyMs: number
  ): BufferHealthState;
  getRecommendedAdjustment(): number;
  reset(): void;
}
