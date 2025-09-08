import {
  IAudioPlayPayload,
  IAudioFrame,
  IFrameProcessor,
} from '../types';

/**
 * Processes base64 PCM audio chunks into timestamped frames.
 * Validates input, sanitizes data, estimates duration.
 */
export class FrameProcessor implements IFrameProcessor {
  private static readonly _sampleRate = 16000; // 16kHz
  private static readonly _bytesPerSample = 2; // 16-bit PCM
  private static readonly _maxReasonableChunkSizeBytes =
    64 * 1024; // 64KB safety
  private static readonly _validBase64Regex =
    /^[A-Za-z0-9+/]*={0,2}$/;

  private _sequenceNumber: number = 0;
  private _frameIntervalMs: number;

  constructor(frameIntervalMs: number = 20) {
    this._frameIntervalMs = frameIntervalMs;
  }

  /** Parse an audio payload into timestamped frames with validation. */
  public parseChunk(
    payload: IAudioPlayPayload
  ): IAudioFrame[] {
    if (!this._isValidPayload(payload)) {
      return [];
    }

    try {
      const sanitizedData = this._sanitizeBase64(
        payload.audioData
      );
      const estimatedDuration =
        this._calculateDuration(sanitizedData);

      const frame: IAudioFrame = {
        sequenceNumber: this._sequenceNumber++,
        data: {
          audioData: sanitizedData,
          isFirst: payload.isFirst ?? false,
          isFinal: payload.isFinal ?? false,
        },
        duration: estimatedDuration,
        timestamp: Date.now(),
      };

      return [frame];
    } catch (error) {
      // Log error if logging is available, otherwise silently handle
      console.warn(
        'FrameProcessor: Failed to parse chunk:',
        error
      );
      return [];
    }
  }

  /** Reset sequence numbering (on stream restart). */
  public reset(): void {
    this._sequenceNumber = 0;
  }

  /** Validate payload structure and content. */
  private _isValidPayload(
    payload: IAudioPlayPayload
  ): boolean {
    if (!payload || typeof payload !== 'object') {
      return false;
    }

    if (
      !payload.audioData ||
      typeof payload.audioData !== 'string'
    ) {
      return false;
    }

    // Quick length check
    if (payload.audioData.length === 0) {
      return false;
    }

    // Estimate decoded size for safety
    const estimatedDecodedSize =
      (payload.audioData.length * 3) / 4;
    if (
      estimatedDecodedSize >
      FrameProcessor._maxReasonableChunkSizeBytes
    ) {
      console.warn(
        'FrameProcessor: Chunk size exceeds reasonable limit:',
        estimatedDecodedSize
      );
      return false;
    }

    return true;
  }

  /** Clean and validate base64 string. */
  private _sanitizeBase64(base64Data: string): string {
    if (!base64Data) {
      throw new Error('Empty base64 data');
    }

    // Remove any whitespace
    const cleaned = base64Data.replace(/\s/g, '');

    // Basic format validation
    if (!FrameProcessor._validBase64Regex.test(cleaned)) {
      throw new Error('Invalid base64 format');
    }

    // Ensure proper padding
    const remainder = cleaned.length % 4;
    if (remainder === 2) {
      return cleaned + '==';
    } else if (remainder === 3) {
      return cleaned + '=';
    }

    return cleaned;
  }

  /** Estimate frame duration from base64 PCM data. */
  private _calculateDuration(base64Data: string): number {
    try {
      // Estimate decoded byte count
      const paddingCount = (base64Data.match(/=/g) || [])
        .length;
      const estimatedBytes =
        (base64Data.length * 3) / 4 - paddingCount;

      // Convert bytes to samples to duration
      const sampleCount =
        estimatedBytes / FrameProcessor._bytesPerSample;
      const durationMs =
        (sampleCount / FrameProcessor._sampleRate) * 1000;

      // Sanity check and fallback to frame interval
      if (durationMs <= 0 || durationMs > 1000) {
        console.warn(
          'FrameProcessor: Calculated duration out of range, using frame interval:',
          durationMs
        );
        return this._frameIntervalMs;
      }

      return Math.round(durationMs);
    } catch (error) {
      console.warn(
        'FrameProcessor: Duration calculation failed, using frame interval:',
        error
      );
      return this._frameIntervalMs;
    }
  }
}
