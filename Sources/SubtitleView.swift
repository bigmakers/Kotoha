//
//  SubtitleView.swift
//  SubtitleApp
//
//  Main landscape subtitle display with ripple effects,
//  auto-fading subtitle lines, and settings access.
//
//  Simplified: SpeechRecognizer now force-restarts after silence,
//  so each segment is treated as final. No more committedLength tracking.
//

import SwiftUI

// MARK: - Scatter State

/// Tracks a "scatter on tap" event — when the user taps, all visible
/// subtitle characters explode outward from the tap point and fade.
struct ScatterState {
    let center: CGPoint
    let startTime: Date
    let duration: TimeInterval = 2.0
    let entryIDs: Set<UUID>

    func progress(now: Date) -> Double {
        let elapsed = now.timeIntervalSince(startTime)
        return min(1.0, max(0.0, elapsed / duration))
    }

    func isComplete(now: Date) -> Bool {
        progress(now: now) >= 1.0
    }
}

// MARK: - Subtitle View

struct SubtitleView: View {

    let settings = SettingsManager.shared
    let audioManager: AudioManager
    let speechRecognizer: SpeechRecognizer
    let rippleEngine = RippleEngine()

    @State private var showSettings = false

    /// Each finalized sentence gets its own entry with a timestamp
    @State private var subtitleEntries: [SubtitleEntry] = []

    /// The live (partial) text currently being recognized
    @State private var currentPartialText: String = ""

    /// Shake trigger — increments each time partial text updates
    @State private var textShake: CGFloat = 0

    // Timer for driving animation
    @State private var now: Date = .now

    /// Active scatter animation (nil = no scatter in progress)
    @State private var activeScatter: ScatterState? = nil

    // Timer for pruning old subtitles
    let pruneTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    let animationTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                settings.backgroundTheme.backgroundColor
                    .ignoresSafeArea()

                // Wagara pattern overlay
                if settings.backgroundTheme.hasPattern {
                    WagaraPatternView()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Canvas-based ripple rings
                CanvasRippleView(
                    engine: rippleEngine,
                    now: now,
                    ringColor: settings.rippleColorTheme.ringColor,
                    glowColor: settings.rippleColorTheme.glowColor
                )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // Subtitle content — centered vertically
                subtitleContent(in: geo)

                // Settings gear button — top-right
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(16)
                        }
                    }
                    Spacer()
                }

                // RMS indicator bar (subtle, bottom-left)
                VStack {
                    Spacer()
                    HStack {
                        RMSIndicator(rms: audioManager.currentRMS)
                            .padding(.leading, 20)
                            .padding(.bottom, 12)
                        Spacer()
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        // Spawn ripple if enabled
                        if settings.rippleEnabled {
                            rippleEngine.addRipple(at: value.location, amplitude: 14.0)
                        }

                        // Scatter all visible subtitle entries
                        if !subtitleEntries.isEmpty {
                            let ids = Set(subtitleEntries.map { $0.id })
                            activeScatter = ScatterState(
                                center: value.location,
                                startTime: .now,
                                entryIDs: ids
                            )
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onReceive(pruneTimer) { _ in
            pruneOldEntries()
        }
        .onReceive(animationTimer) { date in
            now = date
            rippleEngine.pruneExpired()

            // Check if scatter animation finished — remove scattered entries
            if let scatter = activeScatter, scatter.isComplete(now: date) {
                subtitleEntries.removeAll { scatter.entryIDs.contains($0.id) }
                activeScatter = nil
            }
        }
        .onChange(of: speechRecognizer.recognizedText) { oldValue, newValue in
            // recognizedText is now per-session (resets on each restart).
            // Just show it directly as live partial text.
            currentPartialText = newValue

            // Only trigger effects when text actually changed (not empty)
            guard !newValue.isEmpty, newValue != oldValue else { return }

            // Gentle, elegant text sway on new input
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                textShake = CGFloat.random(in: -1.5...1.5)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    textShake = 0
                }
            }

            // Ripple from center of screen
            if settings.rippleEnabled {
                let screenW = UIScreen.main.bounds.width
                let screenH = UIScreen.main.bounds.height
                let rippleX = screenW * 0.5 + CGFloat.random(in: -80...80)
                let rippleY = screenH * 0.5 + CGFloat.random(in: -20...20)
                rippleEngine.addRipple(
                    at: CGPoint(x: rippleX, y: rippleY),
                    amplitude: 6.0
                )
            }
        }
        .onChange(of: speechRecognizer.lastFinalText) { _, newValue in
            guard !newValue.isEmpty else { return }

            // Segment finalized — commit as subtitle
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                commitSubtitle(trimmed)
            }
            currentPartialText = ""

            // Big ripple on sentence finalize — from screen center
            if settings.rippleEnabled {
                let screenW = UIScreen.main.bounds.width
                let screenH = UIScreen.main.bounds.height
                rippleEngine.addRipple(
                    at: CGPoint(x: screenW * 0.5, y: screenH * 0.5),
                    amplitude: 12.0
                )
            }
        }
        .onChange(of: settings.language) { _, _ in
            speechRecognizer.updateLanguage()
        }
        .onAppear {
            setupAudioRippleCallback()
        }
    }

    // MARK: - Subtitle Content (centered on screen)

    @ViewBuilder
    private func subtitleContent(in geo: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            // Show recent finalized sentences (each fades out independently)
            ForEach(Array(subtitleEntries.suffix(3))) { entry in
                let age = now.timeIntervalSince(entry.createdAt)
                let duration = settings.subtitleDuration
                let fadeStart = duration * 0.5
                let opacity = age < fadeStart ? 1.0 : max(0, 1.0 - (age - fadeStart) / (duration - fadeStart))

                // Scatter state for this entry
                let isScattering = activeScatter?.entryIDs.contains(entry.id) == true
                let scatterProgress = isScattering ? (activeScatter?.progress(now: now) ?? 0) : 0
                let scatterCenter = isScattering ? activeScatter?.center : nil

                RippleTextView(
                    text: entry.text,
                    font: settings.subtitleFont,
                    color: settings.textColor,
                    opacity: opacity,
                    engine: rippleEngine,
                    now: now,
                    baseY: geo.size.height * 0.5,
                    scatterCenter: scatterCenter,
                    scatterProgress: scatterProgress
                )
                .padding(.horizontal, 40)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .id(entry.id)
            }

            // Current partial recognition (live text — with input shake + ripple distortion)
            // Note: partial text does NOT scatter — only committed entries do
            if !currentPartialText.isEmpty {
                RippleTextView(
                    text: currentPartialText,
                    font: settings.subtitleFont,
                    color: settings.textColor.opacity(0.7),
                    opacity: 1.0,
                    engine: rippleEngine,
                    now: now,
                    baseY: geo.size.height * 0.5
                )
                .padding(.horizontal, 40)
                .offset(x: textShake, y: textShake * 0.5)
                .scaleEffect(1.0 + abs(textShake) * 0.005)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // center vertically & horizontally
        .animation(.spring(duration: 0.35), value: subtitleEntries.count)
        .animation(.easeInOut(duration: 0.1), value: currentPartialText)
    }

    // MARK: - Helpers

    private func commitSubtitle(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Prevent duplicate: skip if last entry has the same text
        if let last = subtitleEntries.last, last.text == trimmed {
            print("[Subtitle] ⏭️ Skip duplicate: \(trimmed)")
            return
        }

        print("[Subtitle] ✅ Commit: \(trimmed)")
        withAnimation(.spring(duration: 0.35)) {
            let entry = SubtitleEntry(text: trimmed, createdAt: .now)
            subtitleEntries.append(entry)
        }
    }

    private func pruneOldEntries() {
        let duration = settings.subtitleDuration
        let now = Date.now
        let before = subtitleEntries.count
        withAnimation(.easeOut(duration: 0.4)) {
            subtitleEntries.removeAll { entry in
                now.timeIntervalSince(entry.createdAt) > duration
            }
        }
        let after = subtitleEntries.count
        if before != after {
            print("[Subtitle] Pruned \(before - after) entries, remaining: \(after)")
        }
    }

    private func setupAudioRippleCallback() {
        audioManager.onRMSPeak = { [rippleEngine, settings] in
            guard settings.rippleEnabled else { return }
            let x = CGFloat.random(in: 100...700)
            let y = CGFloat.random(in: 100...350)
            rippleEngine.addRipple(at: CGPoint(x: x, y: y), amplitude: 10.0)
        }
    }
}

// MARK: - Per-character Ripple Text View

/// Renders each character individually with ripple-based displacement.
/// When a ripple wave passes through, characters distort and shift.
/// When scatter is active, characters explode outward from the tap point.
/// Automatically wraps text into multiple lines based on screen width.
struct RippleTextView: View {
    let text: String
    let font: Font
    let color: Color
    let opacity: Double
    let engine: RippleEngine
    let now: Date
    let baseY: CGFloat

    // Scatter parameters (nil/0 = no scatter active)
    var scatterCenter: CGPoint? = nil
    var scatterProgress: Double = 0.0

    /// Approximate character width based on font size
    private var charWidth: CGFloat {
        // Japanese full-width characters are nearly square (width ≈ height)
        let settings = SettingsManager.shared
        return settings.fontSize * 0.95
    }

    /// Available width for text (screen width minus horizontal padding)
    private var availableWidth: CGFloat {
        UIScreen.main.bounds.width - 80  // 40pt padding on each side
    }

    /// Maximum characters per line
    private var charsPerLine: Int {
        max(1, Int(availableWidth / charWidth))
    }

    /// Split text into lines that fit the screen width
    private var lines: [[Character]] {
        let chars = Array(text)
        var result: [[Character]] = []
        var start = 0
        while start < chars.count {
            let end = min(start + charsPerLine, chars.count)
            result.append(Array(chars[start..<end]))
            start = end
        }
        return result
    }

    var body: some View {
        let allLines = lines
        VStack(spacing: 2) {
            ForEach(Array(allLines.enumerated()), id: \.offset) { lineIndex, lineChars in
                let globalOffset = allLines.prefix(lineIndex).reduce(0) { $0 + $1.count }
                let lineY = baseY + CGFloat(lineIndex - allLines.count / 2) * (charWidth * 1.6)

                HStack(spacing: 1) {
                    ForEach(Array(lineChars.enumerated()), id: \.offset) { charIndex, char in
                        let globalIndex = globalOffset + charIndex
                        let charX = estimateCharX(
                            index: charIndex,
                            total: lineChars.count
                        )
                        let point = CGPoint(x: charX, y: lineY)
                        let disp = engine.displacement(at: point, now: now)
                        let scatter = scatterDisplacement(
                            charX: charX,
                            charY: lineY,
                            charIndex: globalIndex
                        )

                        Text(String(char))
                            .font(font)
                            .foregroundStyle(color)
                            .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 0)
                            .opacity(opacity * scatter.opacity)
                            .offset(
                                x: disp.width + scatter.dx,
                                y: disp.height + scatter.dy
                            )
                            .scaleEffect((1.0 + abs(disp.height) * 0.002) * scatter.scale)
                            .rotationEffect(.degrees(Double(disp.width) * 0.08 + scatter.rotation))
                    }
                }
            }
        }
    }

    // MARK: - Scatter Physics

    private struct ScatterResult {
        let dx: CGFloat
        let dy: CGFloat
        let opacity: Double
        let scale: CGFloat
        let rotation: Double
    }

    private func scatterDisplacement(charX: CGFloat, charY: CGFloat, charIndex: Int) -> ScatterResult {
        guard let center = scatterCenter, scatterProgress > 0 else {
            return ScatterResult(dx: 0, dy: 0, opacity: 1, scale: 1, rotation: 0)
        }

        // Slow ease-out for gentle, drifting motion
        let t = scatterProgress
        let eased = 1.0 - pow(1.0 - t, 2.0)  // quadratic ease-out (gentler)

        // Direction: each character drifts away from tap center
        let dx = charX - center.x
        let dy = charY - center.y
        let dist = max(sqrt(dx * dx + dy * dy), 1.0)
        let dirX = dx / dist
        let dirY = dy / dist

        // Gentle flight distance (shorter = slower feel)
        let baseFlight: CGFloat = 180.0
        let distanceFactor = min(dist / 250.0, 1.5) + 0.3
        let flight = baseFlight * distanceFactor * CGFloat(eased)

        // Per-character deterministic seed for variety
        let seed = Double(charIndex * 137 + 41)
        let angleJitter = CGFloat(sin(seed) * 0.5)
        let cosA = cos(angleJitter) as CGFloat
        let sinA = sin(angleJitter) as CGFloat
        let jitteredDirX = dirX * cosA - dirY * sinA
        let jitteredDirY = dirX * sinA + dirY * cosA

        // Yurayura — gentle sine wave sway perpendicular to flight direction
        let elapsed = t * 2.0  // actual seconds (duration = 2.0s)
        let swayFreq = 2.5 + sin(seed * 0.7) * 0.8  // slightly different per char
        let swayAmp: CGFloat = 20.0 + CGFloat(sin(seed * 0.3)) * 10.0
        let sway = CGFloat(sin(swayFreq * elapsed * .pi)) * swayAmp * CGFloat(eased)

        // Perpendicular direction for sway
        let perpX = -jitteredDirY
        let perpY = jitteredDirX

        let finalDX = jitteredDirX * flight + perpX * sway
        let finalDY = jitteredDirY * flight + perpY * sway

        // Opacity: gentle fade (start fading at 30%, fully gone by 95%)
        let fadeOpacity = max(0, 1.0 - max(0, (t - 0.3) / 0.65))

        // Scale: slight shrink as they drift
        let scale = max(0.2, 1.0 - eased * 0.4)

        // Rotation: gentle swaying rotation (not spinning, just tilting)
        let rotationDir = cos(seed) > 0 ? 1.0 : -1.0
        let tiltBase = rotationDir * eased * 45.0  // gentle tilt
        let tiltSway = sin(swayFreq * elapsed * .pi) * 15.0  // oscillating tilt
        let rotation = tiltBase + tiltSway

        return ScatterResult(
            dx: CGFloat(finalDX),
            dy: CGFloat(finalDY),
            opacity: fadeOpacity,
            scale: CGFloat(scale),
            rotation: rotation
        )
    }

    // MARK: - Character Position

    private func estimateCharX(index: Int, total: Int) -> CGFloat {
        let screenW = UIScreen.main.bounds.width
        let centerX = screenW * 0.5
        let spacing: CGFloat = 1.0
        let step = charWidth + spacing
        let totalWidth = CGFloat(total) * step - spacing
        let startX = centerX - totalWidth * 0.5
        return startX + CGFloat(index) * step + charWidth * 0.5
    }
}

// MARK: - Canvas-based Ripple Visualization

struct CanvasRippleView: View {
    let engine: RippleEngine
    let now: Date
    var ringColor: Color = .white
    var glowColor: Color = .cyan

    var body: some View {
        Canvas { context, size in
            for ripple in engine.ripples {
                let elapsed = Double(ripple.elapsed(now: now))
                let maxRadius = min(size.width, size.height) * 0.8
                let speed = 280.0

                // Multiple expanding rings per ripple
                for ring in 0..<3 {
                    let delay = Double(ring) * 0.12
                    let t = max(0, elapsed - delay)
                    let radius = t * speed
                    guard radius > 0 && radius < maxRadius else { continue }

                    let lifespan = 2.5
                    let alpha = max(0, 1.0 - t / lifespan) * Double(ripple.amplitude) / 14.0
                    let lineW = max(0.5, 2.5 - t * 0.8)

                    let rect = CGRect(
                        x: ripple.center.x - radius,
                        y: ripple.center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )

                    // Outer ring
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(ringColor.opacity(alpha * 0.35)),
                        lineWidth: lineW
                    )

                    // Inner glow ring
                    let glowRadius = max(0, radius - 8)
                    let glowRect = CGRect(
                        x: ripple.center.x - glowRadius,
                        y: ripple.center.y - glowRadius,
                        width: glowRadius * 2,
                        height: glowRadius * 2
                    )
                    context.stroke(
                        Path(ellipseIn: glowRect),
                        with: .color(glowColor.opacity(alpha * 0.15)),
                        lineWidth: lineW * 2
                    )
                }

                // Center dot flash
                if elapsed < 0.3 {
                    let dotAlpha = 1.0 - elapsed / 0.3
                    let dotSize = 6.0 + elapsed * 20.0
                    let dotRect = CGRect(
                        x: ripple.center.x - dotSize / 2,
                        y: ripple.center.y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(ringColor.opacity(dotAlpha * 0.6))
                    )
                }
            }
        }
    }
}

// MARK: - Wagara (Japanese Pattern) Background

/// Full-screen asanoha (hemp leaf) pattern overlay
struct WagaraPatternView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 40
            let lineColor = Color(red: 0.2, green: 0.12, blue: 0.06)

            for x in stride(from: -step, through: size.width + step, by: step) {
                for y in stride(from: -step, through: size.height + step, by: step) {
                    drawAsanoha(context: &context, x: x, y: y, step: step, color: lineColor)
                }
            }
        }
    }

    private func drawAsanoha(context: inout GraphicsContext, x: CGFloat, y: CGFloat, step: CGFloat, color: Color) {
        let cx = x + step / 2
        let cy = y + step / 2
        let half = step / 2

        // Diamond outline
        let diamond = Path { p in
            p.move(to: CGPoint(x: cx, y: y))
            p.addLine(to: CGPoint(x: x + step, y: cy))
            p.addLine(to: CGPoint(x: cx, y: y + step))
            p.addLine(to: CGPoint(x: x, y: cy))
            p.closeSubpath()
        }
        context.stroke(diamond, with: .color(color.opacity(0.3)), lineWidth: 0.8)

        // Inner lines radiating from center (asanoha style)
        let lines = Path { p in
            // Horizontal & vertical
            p.move(to: CGPoint(x: cx, y: y))
            p.addLine(to: CGPoint(x: cx, y: y + step))
            p.move(to: CGPoint(x: x, y: cy))
            p.addLine(to: CGPoint(x: x + step, y: cy))
            // Diagonals to midpoints
            p.move(to: CGPoint(x: cx, y: cy))
            p.addLine(to: CGPoint(x: cx - half / 2, y: cy - half / 2))
            p.move(to: CGPoint(x: cx, y: cy))
            p.addLine(to: CGPoint(x: cx + half / 2, y: cy - half / 2))
            p.move(to: CGPoint(x: cx, y: cy))
            p.addLine(to: CGPoint(x: cx - half / 2, y: cy + half / 2))
            p.move(to: CGPoint(x: cx, y: cy))
            p.addLine(to: CGPoint(x: cx + half / 2, y: cy + half / 2))
        }
        context.stroke(lines, with: .color(color.opacity(0.2)), lineWidth: 0.5)
    }
}

// MARK: - RMS Level Indicator

struct RMSIndicator: View {
    let rms: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { i in
                let threshold = Float(i) / 12.0 * 0.3
                RoundedRectangle(cornerRadius: 1)
                    .fill(rms > threshold ? barColor(for: i) : .white.opacity(0.15))
                    .frame(width: 3, height: 12)
            }
        }
        .animation(.linear(duration: 0.05), value: rms)
    }

    private func barColor(for index: Int) -> Color {
        if index < 6 { return .green }
        if index < 9 { return .yellow }
        return .red
    }
}
