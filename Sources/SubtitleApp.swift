//
//  SubtitleApp.swift
//  SubtitleApp
//
//  App entry point. Sets up landscape orientation lock
//  and initializes AudioManager + SpeechRecognizer.
//

import SwiftUI
import AVFoundation

@main
struct SubtitleApp: App {

    @State private var audioManager = AudioManager()
    @State private var speechRecognizer = SpeechRecognizer()

    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var pipelineStarted = false

    // Delegate for orientation lock
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            SubtitleView(
                audioManager: audioManager,
                speechRecognizer: speechRecognizer
            )
            .preferredColorScheme(.dark)
            .onAppear {
                // Wire up audio -> speech pipeline
                audioManager.speechRecognizer = speechRecognizer

                // Request both permissions
                requestMicrophonePermission()
                speechRecognizer.requestAuthorization()
            }
            .onChange(of: speechRecognizer.isAuthorized) { _, authorized in
                print("[App] Speech authorization: \(authorized)")
                speechGranted = authorized
                tryStartPipeline()
            }
            .onChange(of: micGranted) { _, granted in
                print("[App] Mic granted: \(granted)")
                tryStartPipeline()
            }
        }
    }

    private func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                print("[App] Mic permission callback: \(granted)")
                micGranted = granted
            }
        }
    }

    private func tryStartPipeline() {
        guard micGranted, speechGranted, !pipelineStarted else {
            print("[App] tryStartPipeline — mic:\(micGranted) speech:\(speechGranted) started:\(pipelineStarted)")
            return
        }
        pipelineStarted = true
        print("[App] ✅ Starting audio + speech pipeline")
        audioManager.start()
        speechRecognizer.startRecognition()
    }
}

// MARK: - AppDelegate for Orientation Lock
//
// This locks the app to landscape only.
// Additionally, in your Xcode project settings:
//   Target > General > Deployment Info > Device Orientation:
//     ☐ Portrait
//     ☑ Landscape Left
//     ☑ Landscape Right
//     ☐ Upside Down

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }
}
