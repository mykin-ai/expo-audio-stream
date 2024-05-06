import Foundation
import AVFoundation
import ExpoModulesCore

public class ExpoAudioStreamModule: Module {
    private let audioContoller = AudioController()
    
    public func definition() -> ModuleDefinition {
        Name("ExpoAudioStream")
        
        AsyncFunction("streamRiff16Khz16BitMonoPcmChunk") { (base64chunk: String, promise: Promise) in
            audioContoller.streamRiff16Khz16BitMonoPcmChunk(base64chunk, resolver: { _ in
                promise.resolve(nil)
            }, rejecter: { code, message, error in
                promise.reject(code ?? "ERR_UNKNOWN", message ?? "Unknown error")
            })
        }
        
        AsyncFunction("setVolume") { (volume: Float, promise: Promise) in
            audioContoller.setVolume(volume, resolver: { _ in
                promise.resolve(nil)
            }, rejecter: { code, message, error in
                promise.reject(code ?? "ERR_VOLUME_ERROR", message ?? "Error setting volume")
            })
        }
        
        AsyncFunction("pause") { promise in
            audioContoller.pause(promise: promise)
        }
        
        AsyncFunction("play") { promise in
            audioContoller.play(promise: promise)
        }
        
        AsyncFunction("stop") { promise in
            audioContoller.stop(promise: promise)
        }
        
        OnCreate {}
    }
}
