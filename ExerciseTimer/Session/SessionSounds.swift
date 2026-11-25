import Foundation
import AVFoundation

/// Audio cues for a running session, moved out of the view so it survives SwiftUI re-renders.
/// Same tones as before; the per-cue player node is now detached after playing (the old code
/// attached a new node to the engine for every beep and never removed it).
@MainActor
final class SessionSounds {
    private let audioEngine = AVAudioEngine()
    private var completionPlayer: AVAudioPlayer?
#if canImport(UIKit)
    private let backgroundNode = AVAudioPlayerNode()
    private(set) var isBackgroundLoopRunning = false
#endif

    func configureSession() {
#if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
#endif
    }

    /// Short C5 chime played at each phase change.
    func playCue() {
        let sampleRate: Double = 44100
        let frequency: Float = 523.0
        let amplitude: Float = 0.22
        let duration: Double = 0.22
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) {
            let t = Double(i) / Double(frameCount - 1)
            let envelope = Float(0.5 * (1.0 - cos(2.0 * .pi * t)))
            let phase = Float(i) * frequency / Float(sampleRate)
            channel[i] = sin(phase * 2 * .pi) * amplitude * envelope
        }

        let node = AVAudioPlayerNode()
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        if !audioEngine.isRunning {
            do { try audioEngine.start() } catch { audioEngine.detach(node); return }
        }
        node.play()
        node.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                node.stop()
                self?.audioEngine.detach(node)
            }
        }
    }

    /// Rising three-tone celebration (C6, E6, G6) for finishing a workout.
    func playCompletion() {
        let sampleRate = 44100
        let toneLength = Int(Double(sampleRate) * 0.18)
        let gapLength = Int(Double(sampleRate) * 0.04)
        let totalFrames = toneLength * 3 + gapLength * 2
        let frequencies: [Double] = [1047.0, 1319.0, 1568.0]
        var pcm = [Int16](repeating: 0, count: totalFrames)
        var offset = 0
        for (n, freq) in frequencies.enumerated() {
            for i in 0..<toneLength {
                let envelope = min(1.0, min(Double(i) / 300, Double(toneLength - i) / 300))
                let phase = Double(i) * freq / Double(sampleRate)
                pcm[offset + i] = Int16(sin(phase * 2 * .pi) * 0.4 * envelope * Double(Int16.max))
            }
            offset += toneLength + (n < 2 ? gapLength : 0)
        }
        let dataSize = totalFrames * 2
        var wav = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: "RIFF".utf8); append(UInt32(36 + dataSize).littleEndian)
        wav.append(contentsOf: "WAVE".utf8); wav.append(contentsOf: "fmt ".utf8)
        append(UInt32(16).littleEndian); append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(UInt32(sampleRate).littleEndian); append(UInt32(sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        wav.append(contentsOf: "data".utf8); append(UInt32(dataSize).littleEndian)
        pcm.withUnsafeBytes { wav.append(contentsOf: $0) }
        completionPlayer = try? AVAudioPlayer(data: wav)
        completionPlayer?.play()
    }

#if canImport(UIKit)
    /// Near-silent loop that keeps the app (and its timers) alive in the background when the
    /// person opts in to "Background Audio".
    func startBackgroundLoop() {
        guard !isBackgroundLoopRunning else { return }
        let sampleRate: Double = 44100
        let frames = AVAudioFrameCount(sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        if !audioEngine.attachedNodes.contains(backgroundNode) {
            audioEngine.attach(backgroundNode)
            audioEngine.connect(backgroundNode, to: audioEngine.mainMixerNode, format: format)
        }
        if !audioEngine.isRunning {
            do { try audioEngine.start() } catch { return }
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { channel[i] = 0.00001 * ((i % 2 == 0) ? 1.0 : -1.0) }
        backgroundNode.play()
        backgroundNode.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        isBackgroundLoopRunning = true
    }

    func stopBackgroundLoop() {
        guard isBackgroundLoopRunning else { return }
        backgroundNode.stop()
        isBackgroundLoopRunning = false
    }
#endif

    func stopAll() {
#if canImport(UIKit)
        stopBackgroundLoop()
#endif
        if audioEngine.isRunning { audioEngine.stop() }
    }
}
