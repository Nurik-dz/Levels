import Foundation

/// What the user chose for one app. Saved per app (by bundle ID), so it comes back next launch.
struct AppSettings: Codable, Equatable {
    var volume: Double = 1            // 0...1.5 (above 1 boosts, with a soft limiter)
    var muted = false
    var eq: [Float] = Array(repeating: 0, count: 10)
    var eqEnabled = true
    var outputUID: String? = nil      // nil = follow the Mac's output

    var hasEQ: Bool { eqEnabled && eq.contains { abs($0) > 0.05 } }
    /// True when the app's sound has to be taken over (anything but untouched).
    var needsProcessing: Bool { abs(volume - 1) > 0.001 || muted || hasEQ || outputUID != nil }

    /// Volume at zero silences the app as surely as Mute does.
    var isSilenced: Bool { muted || volume < 0.005 }

    /// Plain-language list of what was changed, for quiet rows and the Settings list.
    var summary: String {
        var parts: [String] = []
        if muted { parts.append("Muted") }
        else if volume < 0.005 { parts.append("Volume 0%") }
        else if volume > 1.001 { parts.append("Boost \(Int((volume * 100).rounded()))%") }
        else if volume < 0.999 { parts.append("Volume \(Int((volume * 100).rounded()))%") }
        if hasEQ { parts.append("Equalizer") }
        if outputUID != nil { parts.append("Own output") }
        return parts.joined(separator: " · ")
    }

    /// What the slider does not already say: mute, equalizer, own output.
    var extras: String {
        var parts: [String] = []
        if muted { parts.append("Muted") }
        if hasEQ { parts.append("Equalizer") }
        if outputUID != nil { parts.append("Own output") }
        return parts.joined(separator: " · ")
    }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        eq = try c.decodeIfPresent([Float].self, forKey: .eq) ?? Array(repeating: 0, count: 10)
        if eq.count != 10 { eq = Array(repeating: 0, count: 10) }
        eqEnabled = try c.decodeIfPresent(Bool.self, forKey: .eqEnabled) ?? true
        outputUID = try c.decodeIfPresent(String.self, forKey: .outputUID)
    }
    enum Keys: String, CodingKey { case volume, muted, eq, eqEnabled, outputUID }
}

struct EQPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let gains: [Float]

    static let all: [EQPreset] = [
        .init(id: "flat",   name: "Flat",         symbol: "equal",                gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        .init(id: "voice",  name: "Voice",        symbol: "person.wave.2",        gains: [-6, -4, -2, 0, 2, 4, 4, 3, 0, -2]),
        .init(id: "bass",   name: "Bass Boost",   symbol: "waveform.path",        gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        .init(id: "treble", name: "Treble Boost", symbol: "sparkles",             gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        .init(id: "night",  name: "Night",        symbol: "moon.stars",           gains: [-3, -2, 0, 1, 2, 2, 1, 0, -3, -5]),
        .init(id: "music",  name: "Music",        symbol: "music.quarternote.3",  gains: [4, 3, 1, 0, -1, 0, 1, 3, 4, 3]),
    ]
}
