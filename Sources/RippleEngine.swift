//
//  RippleEngine.swift
//  SubtitleApp
//
//  Manages active ripple state (up to 5 concurrent ripples)
//  and provides shader arguments for the Metal distortion effect.
//

import SwiftUI
import Observation

struct Ripple: Identifiable {
    let id = UUID()
    let center: CGPoint
    let startTime: Date
    let amplitude: Float

    func elapsed(now: Date) -> Float {
        Float(now.timeIntervalSince(startTime))
    }
}

@Observable
final class RippleEngine {

    private(set) var ripples: [Ripple] = []

    // Maximum concurrent ripples (matches Metal shader slots)
    private let maxRipples = 5

    // Ripples auto-expire after this duration
    private let rippleLifetime: TimeInterval = 2.5

    /// Add a new ripple at the given point
    func addRipple(at center: CGPoint, amplitude: Float = 12.0) {
        // Prune expired ripples first
        pruneExpired()

        // If at max capacity, drop the oldest
        if ripples.count >= maxRipples {
            ripples.removeFirst()
        }

        ripples.append(Ripple(center: center, startTime: .now, amplitude: amplitude))
    }

    /// Prune ripples that have exceeded their lifetime
    func pruneExpired() {
        let now = Date.now
        ripples.removeAll { now.timeIntervalSince($0.startTime) > rippleLifetime }
    }

    /// Number of active ripples (for shader)
    var activeCount: Float {
        pruneExpired()
        return Float(ripples.count)
    }

    /// Calculate combined displacement at a given point from all active ripples.
    /// Returns (dx, dy) offset in points.
    /// Uses slow, wide waves for an elegant, graceful distortion.
    func displacement(at point: CGPoint, now: Date) -> CGSize {
        var totalDX: CGFloat = 0
        var totalDY: CGFloat = 0

        for ripple in ripples {
            let t = CGFloat(ripple.elapsed(now: now))
            let dx = point.x - ripple.center.x
            let dy = point.y - ripple.center.y
            let dist = sqrt(dx * dx + dy * dy)

            // Slower speed + lower frequency = graceful, flowing wave
            let speed: CGFloat = 160.0
            let frequency: CGFloat = 5.0
            let decayRate: CGFloat = 1.2
            let amp = CGFloat(ripple.amplitude)

            // Wide wave front for smooth, gradual displacement
            let front = speed * t
            let halfWidth: CGFloat = 120.0
            let mask: CGFloat
            if dist < front - halfWidth || dist > front + halfWidth {
                mask = 0
            } else {
                // Smooth cosine bell for elegant falloff
                let d = (dist - front) / halfWidth
                mask = max(0, cos(d * .pi / 2))
            }

            let wave = sin(frequency * dist - speed * t)
            let envelope = amp * exp(-decayRate * t) * exp(-0.001 * dist)

            let displacement = wave * envelope * mask

            // Gentle displacement — mostly vertical, subtle horizontal sway
            totalDY += displacement * 0.6
            totalDX += displacement * 0.2 * (dist > 0.001 ? dx / dist : 0)
        }

        return CGSize(width: totalDX, height: totalDY)
    }
}
