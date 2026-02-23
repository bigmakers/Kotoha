//
//  SpeechRecognizer.swift
//  SubtitleApp
//
//  Real-time speech-to-text using SFSpeechRecognizer.
//  Receives audio buffers from AudioManager and publishes
//  recognized text for the subtitle view.
//
//  Simplified approach: force-restart recognition after a
//  brief silence, treating each segment as a complete sentence.
//  This avoids text accumulation from isFinal never firing.
//

import Speech
import AVFoundation
import Observation

@Observable
final class SpeechRecognizer {

    /// The latest partial text from the CURRENT recognition session.
    /// Resets to "" on every restart.
    private(set) var recognizedText: String = ""

    /// Set when a segment is finalized (either by isFinal or forced restart).
    /// SubtitleView observes this to commit the text.
    private(set) var lastFinalText: String = ""

    // Authorization status
    private(set) var isAuthorized: Bool = false

    @ObservationIgnored private let settings = SettingsManager.shared

    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?

    @ObservationIgnored private var isRecognizing = false
    @ObservationIgnored private var bufferCount = 0

    /// Tracks when recognizedText was last updated (for forced restart)
    @ObservationIgnored private var lastTextUpdateTime: Date = .distantPast

    /// Timer that checks for stale text and forces restart
    @ObservationIgnored private var staleCheckTimer: Timer?

    /// Silence duration before forcing a restart (seconds)
    private let forceRestartDelay: TimeInterval = 1.0

    // MARK: - Authorization

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                let authorized = (status == .authorized)
                print("[Speech] Authorization status: \(status.rawValue) -> authorized=\(authorized)")
                self?.isAuthorized = authorized
            }
        }
    }

    // MARK: - Start / Stop

    func startRecognition() {
        guard isAuthorized else {
            print("[Speech] ❌ Not authorized, cannot start")
            return
        }
        guard !isRecognizing else {
            print("[Speech] Already recognizing, skipping start")
            return
        }

        let langID = settings.language.rawValue
        let locale = Locale(identifier: langID)
        recognizer = SFSpeechRecognizer(locale: locale)

        guard let recognizer else {
            print("[Speech] ❌ Could not create recognizer for \(langID)")
            return
        }

        print("[Speech] Recognizer created for \(langID), available=\(recognizer.isAvailable), onDevice=\(recognizer.supportsOnDeviceRecognition)")

        guard recognizer.isAvailable else {
            print("[Speech] ❌ Recognizer not available")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // On-device recognition has lower latency (better for first words)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            print("[Speech] Using on-device recognition (low latency)")
        }

        // Task hint improves accuracy for continuous speech
        recognizer.defaultTaskHint = .dictation

        // Set contextual strings from specialized terms
        let terms = settings.specialTerms
        if !terms.isEmpty {
            request.contextualStrings = terms
            print("[Speech] Set \(terms.count) contextual strings")
        }

        request.addsPunctuation = true
        recognitionRequest = request
        bufferCount = 0
        lastTextUpdateTime = .distantPast

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    print("[Speech] 📝 Text: \(text) (isFinal=\(result.isFinal))")
                    self.recognizedText = text
                    self.lastTextUpdateTime = .now

                    if result.isFinal {
                        // Natural isFinal — commit and restart
                        print("[Speech] ✅ isFinal=true, committing")
                        self.forceFinalize()
                    }
                }
            }

            if let error {
                print("[Speech] ⚠️ Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.restartRecognition()
                }
            }
        }

        isRecognizing = true
        startStaleCheckTimer()
        print("[Speech] ✅ Recognition started for \(langID)")
    }

    func stopRecognition() {
        stopStaleCheckTimer()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecognizing = false
        print("[Speech] Stopped (buffers received: \(bufferCount))")
    }

    /// Called by AudioManager to feed audio buffers
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
        bufferCount += 1
        if bufferCount == 1 {
            print("[Speech] 🎤 First audio buffer received")
        }
        if bufferCount % 100 == 0 {
            print("[Speech] 🎤 Buffer count: \(bufferCount)")
        }
    }

    // MARK: - Forced Finalization

    /// Force-finalize the current text and restart recognition.
    /// This is called when text hasn't changed for `forceRestartDelay` seconds.
    private func forceFinalize() {
        let text = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            restartRecognition()
            return
        }

        print("[Speech] 🔄 Force finalizing: \(text)")
        lastFinalText = text
        restartRecognition()
    }

    // MARK: - Stale Check Timer

    private func startStaleCheckTimer() {
        stopStaleCheckTimer()
        staleCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkForStaleText()
        }
    }

    private func stopStaleCheckTimer() {
        staleCheckTimer?.invalidate()
        staleCheckTimer = nil
    }

    private func checkForStaleText() {
        guard isRecognizing else { return }
        guard !recognizedText.isEmpty else { return }
        guard lastTextUpdateTime != .distantPast else { return }

        let elapsed = Date.now.timeIntervalSince(lastTextUpdateTime)
        if elapsed >= forceRestartDelay {
            print("[Speech] ⏰ Text stale for \(String(format: "%.1f", elapsed))s, force finalizing")
            forceFinalize()
        }
    }

    // MARK: - Restart (for continuous recognition)

    private func restartRecognition() {
        stopRecognition()
        recognizedText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            print("[Speech] 🔄 Restarting recognition...")
            self?.startRecognition()
        }
    }

    /// Called when language setting changes — restart with new locale
    func updateLanguage() {
        guard isRecognizing else { return }
        restartRecognition()
    }
}
