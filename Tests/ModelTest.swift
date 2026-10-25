import Foundation
import AppKit

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String) {
    print(ok ? "PASS" : "FAIL", name, "-", detail); if !ok { failures += 1 }
}
func spin(_ secs: Double) { RunLoop.current.run(until: Date().addingTimeInterval(secs)) }
func spin(until cond: () -> Bool, timeout: Double = 10) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end { if cond() { return true }; spin(0.1) }
    return cond()
}

let NSApplicationShared = NSApplication.shared
NSApplicationShared.setActivationPolicy(.accessory)
let tone = Process()
tone.executableURL = URL(fileURLWithPath: CommandLine.arguments[1] + "/Contents/MacOS/ToneApp")
try! tone.run()

MainActor.assumeIsolated {
    let model = MixerModel()
    model.isPanelVisible = true
    let found = spin(until: { model.apps.contains { $0.app.name == "ToneApp" && $0.isPlaying } })
    check("Levels finds the app that is playing", found, model.apps.map(\.app.name).joined(separator: ", "))
    guard let row = model.apps.first(where: { $0.app.name == "ToneApp" }) else { tone.terminate(); exit(1) }
    let id = row.id

    _ = spin(until: { model.hasLiveConnection(id) })
    spin(0.8)
    let base = model.level(for: id)
    check("meter shows the app's real level", abs(base - 0.5) < 0.05, "peak \(base) (tone is 0.5)")

    model.change(id) { $0.volume = 0.25 }
    spin(1.5)
    let low = model.level(for: id)
    check("volume 25% takes effect", abs(low - 0.125) < 0.02, "peak \(low) (expected 0.125)")

    model.change(id) { $0.muted = true }
    spin(1.0)
    check("mute", model.level(for: id) < 0.005, "peak \(model.level(for: id))")
    check("row says Muted state is stored", model.settings(for: id).muted, "")

    model.change(id) { $0.muted = false; $0.volume = 0.5 }
    var eq = [Float](repeating: 0, count: 10); eq[5] = 6
    model.change(id) { $0.eq = eq }
    spin(1.5)
    let withEQ = model.level(for: id)
    check("EQ changes the sound on top of volume 50%", withEQ > 0.26 && withEQ < 0.45, "peak \(withEQ): above 0.25 (volume alone), as the +6 dB band at 1 kHz lifts 440 Hz slightly")

    // saved for next launch
    let again = MixerModel()
    check("settings are remembered", abs(again.settings(for: id).volume - 0.5) < 0.001 && again.settings(for: id).eq[5] == 6, "volume \(again.settings(for: id).volume)")
    again.shutdown()

    model.reset(id)
    spin(1.5)
    let back = model.level(for: id)
    check("reset returns the original sound", abs(back - 0.5) < 0.05, "peak \(back)")

    model.isPanelVisible = false
    spin(0.8)
    check("no connection while the panel is closed and nothing is changed", !model.hasLiveConnection(id), "live = \(model.hasLiveConnection(id))")
    model.shutdown()
}
tone.terminate()
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
