//
//  RippleShader.metal
//  SubtitleApp
//
//  Metal shader for water-ripple distortion effect.
//  Used with SwiftUI's .distortionEffect modifier (iOS 17+).
//

#include <metal_stdlib>
using namespace metal;

// -------------------------------------------------------
// Multi-ripple distortion (supports up to 5 concurrent ripples)
//
// SwiftUI .distortionEffect automatically provides:
//   position (float2) - current pixel position
//   bounds   (float4) - bounding rect of the view
//
// Custom parameters passed from Swift:
//   count      - number of active ripples (0-5)
//   c0..c4     - center positions
//   t0..t4     - elapsed times
//   a0..a4     - amplitude values
// -------------------------------------------------------
[[ stitchable ]]
float2 multiRipple(
    float2 position,
    float4 bounds,
    float count,
    float2 c0, float t0, float a0,
    float2 c1, float t1, float a1,
    float2 c2, float t2, float a2,
    float2 c3, float t3, float a3,
    float2 c4, float t4, float a4
) {
    float2 totalOffset = float2(0.0);

    float frequency = 14.0;
    float decayRate = 1.8;
    float speed = 300.0;

    int n = clamp(int(count), 0, 5);

    // Ripple 0
    if (n > 0) {
        float2 delta = position - c0;
        float dist = length(delta);
        float wave = sin(frequency * dist - speed * t0);
        float envelope = a0 * exp(-decayRate * t0) * exp(-0.003 * dist);
        float front = speed * t0;
        float mask = smoothstep(front - 50.0, front, dist) *
                     (1.0 - smoothstep(front, front + 50.0, dist));
        if (dist > 0.001) {
            totalOffset += normalize(delta) * wave * envelope * mask;
        }
    }

    // Ripple 1
    if (n > 1) {
        float2 delta = position - c1;
        float dist = length(delta);
        float wave = sin(frequency * dist - speed * t1);
        float envelope = a1 * exp(-decayRate * t1) * exp(-0.003 * dist);
        float front = speed * t1;
        float mask = smoothstep(front - 50.0, front, dist) *
                     (1.0 - smoothstep(front, front + 50.0, dist));
        if (dist > 0.001) {
            totalOffset += normalize(delta) * wave * envelope * mask;
        }
    }

    // Ripple 2
    if (n > 2) {
        float2 delta = position - c2;
        float dist = length(delta);
        float wave = sin(frequency * dist - speed * t2);
        float envelope = a2 * exp(-decayRate * t2) * exp(-0.003 * dist);
        float front = speed * t2;
        float mask = smoothstep(front - 50.0, front, dist) *
                     (1.0 - smoothstep(front, front + 50.0, dist));
        if (dist > 0.001) {
            totalOffset += normalize(delta) * wave * envelope * mask;
        }
    }

    // Ripple 3
    if (n > 3) {
        float2 delta = position - c3;
        float dist = length(delta);
        float wave = sin(frequency * dist - speed * t3);
        float envelope = a3 * exp(-decayRate * t3) * exp(-0.003 * dist);
        float front = speed * t3;
        float mask = smoothstep(front - 50.0, front, dist) *
                     (1.0 - smoothstep(front, front + 50.0, dist));
        if (dist > 0.001) {
            totalOffset += normalize(delta) * wave * envelope * mask;
        }
    }

    // Ripple 4
    if (n > 4) {
        float2 delta = position - c4;
        float dist = length(delta);
        float wave = sin(frequency * dist - speed * t4);
        float envelope = a4 * exp(-decayRate * t4) * exp(-0.003 * dist);
        float front = speed * t4;
        float mask = smoothstep(front - 50.0, front, dist) *
                     (1.0 - smoothstep(front, front + 50.0, dist));
        if (dist > 0.001) {
            totalOffset += normalize(delta) * wave * envelope * mask;
        }
    }

    return position + totalOffset;
}
