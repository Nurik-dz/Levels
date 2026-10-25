import Foundation
import os

/// Centre frequencies of the ten-band equaliser.
enum EQBands {
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let labels = ["31", "62", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    static let range: ClosedRange<Float> = -12...12
}

/// Values the user changes, shared with the audio thread. The audio thread only
/// ever try-locks, so a slider drag can never make the sound stutter.
final class TapParams: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private(set) var version = 0
    private var _volume: Float = 1
    private var _muted = false
    private var _eq = [Float](repeating: 0, count: 10)
    private var _eqEnabled = true

    func update(volume: Float, muted: Bool, eq: [Float], eqEnabled: Bool) {
        os_unfair_lock_lock(&lock)
        _volume = volume; _muted = muted; _eq = eq; _eqEnabled = eqEnabled
        version += 1
        os_unfair_lock_unlock(&lock)
    }

    /// Audio thread: returns nil when the lock is busy or nothing changed.
    func snapshotIfChanged(since seen: Int) -> (version: Int, volume: Float, muted: Bool, eq: [Float], eqEnabled: Bool)? {
        guard os_unfair_lock_trylock(&lock) else { return nil }
        defer { os_unfair_lock_unlock(&lock) }
        guard version != seen else { return nil }
        return (version, _volume, _muted, _eq, _eqEnabled)
    }
}

/// Peaking filter (RBJ cookbook), one band.
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0

    static func peaking(frequency f: Float, gainDB: Float, q: Float, sampleRate: Float) -> Biquad {
        let a = powf(10, gainDB / 40)
        let w = 2 * Float.pi * min(f, sampleRate * 0.45) / sampleRate
        let alpha = sinf(w) / (2 * q)
        let c = cosf(w)
        let a0 = 1 + alpha / a
        return Biquad(b0: (1 + alpha * a) / a0, b1: (-2 * c) / a0, b2: (1 - alpha * a) / a0,
                      a1: (-2 * c) / a0, a2: (1 - alpha / a) / a0)
    }
}

/// Per-channel filter memory for one band.
struct BiquadState { var z1: Float = 0, z2: Float = 0 }

/// Everything that happens to a stereo block between "app's sound" and "your speakers".
/// Allocation-free after init, so it is safe to call from the audio thread.
final class StereoProcessor {
    let params = TapParams()
    private var seenVersion = -1
    private var sampleRate: Float
    private var gain: Float = 1
    private var targetGain: Float = 1
    private var coeffs = [Biquad](repeating: Biquad(), count: 10)
    private var active = [Bool](repeating: false, count: 10)
    private var stateL = [BiquadState](repeating: BiquadState(), count: 10)
    private var stateR = [BiquadState](repeating: BiquadState(), count: 10)
    private var anyBand = false
    private var primed = false

    init(sampleRate: Double) { self.sampleRate = Float(sampleRate) }

    func setSampleRate(_ r: Double) { sampleRate = Float(r); seenVersion = -1 }

    /// Process `frames` samples in place and return the peak of the result.
    func process(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, frames: Int) -> Float {
        if let s = params.snapshotIfChanged(since: seenVersion) {
            seenVersion = s.version
            targetGain = s.muted ? 0 : s.volume
            if !primed { gain = targetGain; primed = true }
            anyBand = false
            for i in 0..<10 {
                let g = s.eqEnabled ? s.eq[i] : 0
                active[i] = abs(g) > 0.05
                if active[i] {
                    coeffs[i] = Biquad.peaking(frequency: EQBands.frequencies[i], gainDB: g, q: 1.41, sampleRate: sampleRate)
                    anyBand = true
                }
            }
        }
        var peak: Float = 0
        let smooth: Float = 0.002
        for n in 0..<frames {
            var x = l[n], y = r[n]
            if anyBand {
                for b in 0..<10 where active[b] {
                    let c = coeffs[b]
                    let ol = c.b0 * x + stateL[b].z1
                    stateL[b].z1 = c.b1 * x - c.a1 * ol + stateL[b].z2
                    stateL[b].z2 = c.b2 * x - c.a2 * ol
                    x = ol
                    let or = c.b0 * y + stateR[b].z1
                    stateR[b].z1 = c.b1 * y - c.a1 * or + stateR[b].z2
                    stateR[b].z2 = c.b2 * y - c.a2 * or
                    y = or
                }
            }
            gain += (targetGain - gain) * smooth
            x = Self.softLimit(x * gain)
            y = Self.softLimit(y * gain)
            l[n] = x; r[n] = y
            peak = max(peak, abs(x), abs(y))
        }
        return peak
    }

    @inline(__always)
    static func softLimit(_ v: Float) -> Float {
        let a = abs(v)
        if a <= 0.9 { return v }
        let s = 0.9 + 0.1 * tanhf((a - 0.9) / 0.1)
        return v < 0 ? -s : s
    }
}
