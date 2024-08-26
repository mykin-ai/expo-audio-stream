import Foundation
import AVFoundation
import ExpoModulesCore

public class ExpoPlayAudioStreamModule: Module {
    private let audioController = AudioController()

    public func definition() -> ModuleDefinition {
        Name("ExpoPlayAudioStream")

        AsyncFunction("streamRiff16Khz16BitMonoPcmChunk") { (base64chunk: String, promise: Promise) in
            audioController.streamRiff16Khz16BitMonoPcmChunk(base64chunk, resolver: { _ in
                promise.resolve(nil)
            }, rejecter: { code, message, error in
                promise.reject(code ?? "ERR_UNKNOWN", message ?? "Unknown error")
            })
        }

        AsyncFunction("setVolume") { (volume: Float, promise: Promise) in
            audioController.setVolume(volume, resolver: { _ in
                promise.resolve(nil)
            }, rejecter: { code, message, error in
                promise.reject(code ?? "ERR_VOLUME_ERROR", message ?? "Error setting volume")
            })
        }

        AsyncFunction("pause") { promise in
            audioController.pause(promise: promise)
        }

        AsyncFunction("play") { promise in
            audioController.play(promise: promise)
        }

        AsyncFunction("stop") { promise in
            audioController.stop(promise: promise)
        }

        OnCreate {}
    }
}
