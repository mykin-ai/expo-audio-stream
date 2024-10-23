// RecordingSettings.swift

struct RecordingSettings {
    var sampleRate: Double
    var desiredSampleRate: Double
    var numberOfChannels: Int = 1
    var bitDepth: Int = 16
    var maxRecentDataDuration: Double? = 10.0 // Default to 10 seconds
    var pointsPerSecond: Int? = 1000 // Default value
}

