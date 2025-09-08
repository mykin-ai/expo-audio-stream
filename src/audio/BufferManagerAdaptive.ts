import { AudioBufferManager } from "./BufferManagerCore";
import { QualityMonitor } from "./QualityMonitor";
import {
  IAudioBufferConfig,
  IAudioPlayPayload,
  SmartBufferMode,
  NetworkConditions,
  SmartBufferConfig,
  IBufferHealthMetrics,
  Encoding,
  EncodingTypes,
} from "../types";

/**
 * Smart buffering manager that automatically adapts to network conditions
 */
export class BufferManagerAdaptive {
  private _mode: SmartBufferMode;
  private _bufferManager: AudioBufferManager | null = null;
  private _networkMonitor: QualityMonitor;
  private _isBufferingEnabled: boolean = false;
  private _networkConditions: NetworkConditions = {};
  private _adaptiveThresholds: Required<
    SmartBufferConfig["adaptiveThresholds"]
  >;
  private _turnId: string;
  private _encoding: Encoding;
  private _lastDecisionTime: number = 0;
  private _consecutiveProblems: number = 0;

  constructor(
    config: SmartBufferConfig,
    turnId: string,
    encoding: Encoding = EncodingTypes.PCM_S16LE
  ) {
    this._mode = config.mode;
    this._turnId = turnId;
    this._encoding = encoding;
    this._networkMonitor = new QualityMonitor();

    // Set default adaptive thresholds
    this._adaptiveThresholds = {
      highLatencyMs: config.adaptiveThresholds?.highLatencyMs ?? 150,
      highJitterMs: config.adaptiveThresholds?.highJitterMs ?? 50,
      packetLossPercent: config.adaptiveThresholds?.packetLossPercent ?? 1.0,
    };

    if (config.networkConditions) {
      this._networkConditions = {
        ...config.networkConditions,
      };
    }

    // Initialize buffering state based on mode
    this._evaluateBufferingNeed();
  }

  /**
   * Process an audio chunk, automatically deciding whether to buffer or play directly
   */
  public async processAudioChunk(
    audioData: IAudioPlayPayload,
    directPlayCallback: (
      data: string,
      turnId: string,
      encoding: Encoding
    ) => Promise<void>
  ): Promise<void> {
    // Update network conditions from the quality monitor
    this._updateNetworkConditions();

    // Re-evaluate buffering need periodically or when conditions change
    if (Date.now() - this._lastDecisionTime > 5000) {
      // Re-evaluate every 5 seconds
      this._evaluateBufferingNeed();
      this._lastDecisionTime = Date.now();
    }

    if (this._isBufferingEnabled) {
      // Use buffered playback
      if (!this._bufferManager) {
        this._initializeBuffering();
      }
      this._bufferManager!.enqueueFrames(audioData);
    } else {
      // Use direct playback
      if (this._bufferManager) {
        this._disableBuffering();
      }
      await directPlayCallback(
        audioData.audioData,
        this._turnId,
        this._encoding
      );
    }
  }

  /**
   * Update network conditions from quality monitor and external sources
   */
  private _updateNetworkConditions(): void {
    const metrics = this._networkMonitor.getMetrics();

    // Update conditions from quality monitor
    this._networkConditions.jitter = metrics.averageJitter;

    // Track consecutive quality problems
    if (
      metrics.bufferHealthState === "degraded" ||
      metrics.bufferHealthState === "critical"
    ) {
      this._consecutiveProblems++;
    } else {
      this._consecutiveProblems = Math.max(0, this._consecutiveProblems - 1);
    }
  }

  /**
   * Evaluate whether buffering should be enabled based on current conditions and mode
   */
  private _evaluateBufferingNeed(): void {
    const previousState = this._isBufferingEnabled;

    switch (this._mode) {
      case "conservative":
        this._isBufferingEnabled = this._shouldBufferConservative();
        break;
      case "balanced":
        this._isBufferingEnabled = this._shouldBufferBalanced();
        break;
      case "aggressive":
        this._isBufferingEnabled = this._shouldBufferAggressive();
        break;
      case "adaptive":
        this._isBufferingEnabled = this._shouldBufferAdaptive();
        break;
    }

    // Log state changes for debugging
    if (previousState !== this._isBufferingEnabled) {
      console.log(
        `[SmartBufferManager] Buffering ${
          this._isBufferingEnabled ? "enabled" : "disabled"
        } for turnId: ${this._turnId} (mode: ${this._mode})`
      );
    }
  }

  private _shouldBufferConservative(): boolean {
    // Only buffer on clear network problems
    return (
      (this._networkConditions.latency !== undefined &&
        this._networkConditions.latency >
          this._adaptiveThresholds!.highLatencyMs * 1.5) ||
      (this._networkConditions.packetLoss !== undefined &&
        this._networkConditions.packetLoss >
          this._adaptiveThresholds!.packetLossPercent * 2) ||
      this._consecutiveProblems > 3
    );
  }

  private _shouldBufferBalanced(): boolean {
    // Buffer on moderate network issues
    return (
      (this._networkConditions.latency !== undefined &&
        this._networkConditions.latency >
          this._adaptiveThresholds!.highLatencyMs) ||
      (this._networkConditions.jitter !== undefined &&
        this._networkConditions.jitter >
          this._adaptiveThresholds!.highJitterMs) ||
      (this._networkConditions.packetLoss !== undefined &&
        this._networkConditions.packetLoss >
          this._adaptiveThresholds!.packetLossPercent) ||
      this._consecutiveProblems > 2
    );
  }

  private _shouldBufferAggressive(): boolean {
    // Buffer proactively on any signs of network issues
    return (
      (this._networkConditions.latency !== undefined &&
        this._networkConditions.latency >
          this._adaptiveThresholds!.highLatencyMs * 0.7) ||
      (this._networkConditions.jitter !== undefined &&
        this._networkConditions.jitter >
          this._adaptiveThresholds!.highJitterMs * 0.5) ||
      (this._networkConditions.packetLoss !== undefined &&
        this._networkConditions.packetLoss > 0.1) ||
      this._consecutiveProblems > 1
    );
  }

  private _shouldBufferAdaptive(): boolean {
    // Dynamic decision based on recent performance
    const recentMetrics = this._networkMonitor.getMetrics();

    // Start with balanced approach
    let shouldBuffer = this._shouldBufferBalanced();

    // Adapt based on recent buffer health
    if (recentMetrics.bufferHealthState === "critical") {
      shouldBuffer = true; // Always buffer on critical issues
    } else if (
      recentMetrics.bufferHealthState === "healthy" &&
      this._consecutiveProblems === 0
    ) {
      shouldBuffer = false; // Disable if consistently healthy
    }

    return shouldBuffer;
  }

  /**
   * Initialize buffering with appropriate configuration
   */
  private _initializeBuffering(): void {
    const bufferConfig: Partial<IAudioBufferConfig> =
      this._getBufferConfigForConditions();

    this._bufferManager = new AudioBufferManager(bufferConfig);
    this._bufferManager.setTurnId(this._turnId);
    this._bufferManager.setEncoding(this._encoding);
    this._bufferManager.startPlayback();

    console.log(
      `[SmartBufferManager] Initialized buffering with config:`,
      bufferConfig
    );
  }

  /**
   * Disable buffering and clean up
   */
  private _disableBuffering(): void {
    if (this._bufferManager) {
      this._bufferManager.stopPlayback();
      this._bufferManager.destroy();
      this._bufferManager = null;
      console.log(
        `[SmartBufferManager] Disabled buffering for turnId: ${this._turnId}`
      );
    }
  }

  /**
   * Get appropriate buffer configuration based on network conditions
   */
  private _getBufferConfigForConditions(): Partial<IAudioBufferConfig> {
    const baseConfig: Partial<IAudioBufferConfig> = {
      frameIntervalMs: 20,
    };

    // Adjust buffer size based on network conditions
    if (this._networkConditions.latency !== undefined) {
      if (this._networkConditions.latency > 200) {
        // High latency - use larger buffer
        baseConfig.targetBufferMs = 400;
        baseConfig.minBufferMs = 200;
        baseConfig.maxBufferMs = 800;
      } else if (this._networkConditions.latency > 100) {
        // Medium latency - use medium buffer
        baseConfig.targetBufferMs = 300;
        baseConfig.minBufferMs = 150;
        baseConfig.maxBufferMs = 600;
      } else {
        // Low latency - use smaller buffer
        baseConfig.targetBufferMs = 240;
        baseConfig.minBufferMs = 120;
        baseConfig.maxBufferMs = 480;
      }
    }

    // Adjust for jitter
    if (
      this._networkConditions.jitter !== undefined &&
      this._networkConditions.jitter > this._adaptiveThresholds!.highJitterMs
    ) {
      // High jitter - increase buffer sizes
      baseConfig.targetBufferMs = (baseConfig.targetBufferMs || 240) * 1.5;
      baseConfig.maxBufferMs = (baseConfig.maxBufferMs || 480) * 1.5;
    }

    return baseConfig;
  }

  /**
   * Update network conditions externally (e.g., from network monitoring)
   */
  public updateNetworkConditions(conditions: Partial<NetworkConditions>): void {
    this._networkConditions = {
      ...this._networkConditions,
      ...conditions,
    };
    this._evaluateBufferingNeed();
  }

  /**
   * Get current buffer health metrics
   */
  public getHealthMetrics(): IBufferHealthMetrics | null {
    if (this._bufferManager) {
      return this._bufferManager.getHealthMetrics();
    }

    // Return basic metrics from network monitor when not buffering
    return {
      currentBufferMs: 0,
      targetBufferMs: 0,
      underrunCount: 0,
      overrunCount: 0,
      averageJitter: this._networkConditions.jitter || 0,
      bufferHealthState: "idle",
      adaptiveAdjustmentsCount: 0,
    };
  }

  /**
   * Check if buffering is currently enabled
   */
  public isBufferingEnabled(): boolean {
    return this._isBufferingEnabled;
  }

  /**
   * Stop and clean up
   */
  public destroy(): void {
    this._disableBuffering();
    this._networkMonitor.reset();
  }
}
