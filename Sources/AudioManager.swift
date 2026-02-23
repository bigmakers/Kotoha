//
//  AudioManager.swift
//  SubtitleApp
//
//  Captures microphone audio via AVAudioEngine.
//  Calculates RMS for ripple triggers and feeds buffers
//  to SpeechRecognizer for real-time transcription.
//

import AVFoundation
import Observation

@Observable
final class AudioManager {

    // Current RMS level (0.0 – 1.0 range, smoothed)
    private(set) var currentRMS: Float = 0.0

    // Fires when RMS exceeds the threshold
    @ObservationIgnored var onRMSPeak: (() -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var isRunning = false

    /// Reference to the speech recognizer so we can feed audio buffers
    @ObservationIgnored weak var speechRecognizer: SpeechRecognizer?

    @ObservationIgnored private let settings = SettingsManager.shared
    @ObservationIgnored private let smoothingFactor: Float = 0.3
    @ObservationIgnored private var lastPeakTime: Date = .distantPast
    @ObservationIgnored private let peakCooldown: TimeInterval = 0.3

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else {
            print("[Audio] Already running")
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[Audio] ✅ Audio session configured")
        } catch {
            print("[Audio] ❌ Failed to configure audio session: \(error)")
            return
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("[Audio] Recording format: \(recordingFormat)")
        print("[Audio] SpeechRecognizer linked: \(speechRecognizer != nil)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            isRunning = true
            print("[Audio] ✅ Engine started")
        } catch {
            print("[Audio] ❌ Failed to start engine: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    // MARK: - Buffer Processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        // Feed buffer to speech recognizer
        speechRecognizer?.appendBuffer(buffer)

        // Calculate RMS
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        var sum: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(max(frameCount, 1)))

        // Smooth and publish on main thread
        let smoothed = smoothingFactor * rms + (1.0 - smoothingFactor) * currentRMS

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentRMS = smoothed

            // Check threshold for ripple trigger
            let threshold = Float(self.settings.rmsThreshold)
            let now = Date()
            if smoothed > threshold,
               now.timeIntervalSince(self.lastPeakTime) > self.peakCooldown {
                self.lastPeakTime = now
                self.onRMSPeak?()
            }
        }
    }
}
