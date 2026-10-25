import Foundation
import CoreAudio
import AudioToolbox

func db(_ x: Float) -> String { String(format: "%.1f dB", 20 * log10f(max(x, 1e-6))) }
var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String) {
    print(ok ? "PASS" : "FAIL", name, "-", detail)
    if !ok { failures += 1 }
}

// ---- Part 1: the maths, offline ----
func sine(_ hz: Float, amp: Float, frames: Int, rate: Float = 48000) -> [Float] {
    (0..<frames).map { amp * sinf(2 * .pi * hz * Float($0) / rate) }
}
func run(_ p: StereoProcessor, _ input: [Float]) -> Float {
    let n = input.count
    let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
    defer { l.deallocate(); r.deallocate() }
    for i in 0..<n { l[i] = input[i]; r[i] = input[i] }
    var peak: Float = 0
    let block = 512
    var i = 0
    while i + block <= n {
        let pk = p.process(l + i, r + i, frames: block)
        if i > n - 48000 { peak = max(peak, pk) }   // measure the last second, after settling
        i += block
    }
    return peak
}
do {
    let p = StereoProcessor(sampleRate: 48000)
    p.params.update(volume: 0.5, muted: false, eq: Array(repeating: 0, count: 10), eqEnabled: true)
    let pk = run(p, sine(1000, amp: 0.5, frames: 96000))
    check("volume 50%", abs(pk - 0.25) < 0.01, "0.5 in -> \(pk) out (\(db(pk)))")
}
do {
    let p = StereoProcessor(sampleRate: 48000)
    p.params.update(volume: 1, muted: true, eq: Array(repeating: 0, count: 10), eqEnabled: true)
    let pk = run(p, sine(1000, amp: 0.5, frames: 96000))
    check("mute", pk < 0.001, "peak \(pk)")
}
do {
    var eq = [Float](repeating: 0, count: 10); eq[5] = 12   // +12 dB at 1 kHz
    let p = StereoProcessor(sampleRate: 48000)
    p.params.update(volume: 1, muted: false, eq: eq, eqEnabled: true)
    let pk = run(p, sine(1000, amp: 0.1, frames: 96000))
    check("EQ +12 dB at 1 kHz", abs(pk / 0.1 - 3.98) < 0.3, "gain x\(pk / 0.1) (\(db(pk / 0.1)))")
    let p2 = StereoProcessor(sampleRate: 48000)
    p2.params.update(volume: 1, muted: false, eq: eq, eqEnabled: true)
    let far = run(p2, sine(100, amp: 0.1, frames: 96000))
    check("EQ leaves far bands alone", abs(far / 0.1 - 1) < 0.15, "100 Hz gain x\(far / 0.1)")
}
do {
    let p = StereoProcessor(sampleRate: 48000)
    p.params.update(volume: 1.5, muted: false, eq: Array(repeating: 0, count: 10), eqEnabled: true)
    let pk = run(p, sine(1000, amp: 0.95, frames: 96000))
    check("boost never clips", pk <= 1.0, "0.95 x1.5 -> peak \(pk)")
}

// ---- Part 2: live, through the real Mac audio system ----
let wavPath = NSTemporaryDirectory() + "levels_tone.wav"
do {
    let rate = 44100, secs = 14
    var data = Data()
    func u32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: Int) { var x = UInt16(v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
    let n = rate * secs
    data.append("RIFF".data(using: .ascii)!); u32(36 + n * 4); data.append("WAVEfmt ".data(using: .ascii)!)
    u32(16); u16(1); u16(2); u32(rate); u32(rate * 4); u16(4); u16(16)
    data.append("data".data(using: .ascii)!); u32(n * 4)
    for i in 0..<n {
        let s = Int16(0.5 * 32767 * sin(2 * .pi * 440 * Double(i) / Double(rate)))
        u16(Int(UInt16(bitPattern: s))); u16(Int(UInt16(bitPattern: s)))
    }
    try! data.write(to: URL(fileURLWithPath: wavPath))
}
let player = Process()
player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
player.arguments = [wavPath, "-v", "0.5"]    // afplay volume is 0.5 so the source is a known level
try! player.run()
Thread.sleep(forTimeInterval: 1.0)

let found = Processes.all().first { $0.pid == player.processIdentifier }
check("afplay is visible to the audio system", found != nil, "pid \(player.processIdentifier)")
if let found {
    // What does the engine send out? Tap our own process to find out.
    var myObj = AudioObjectID(0)
    var pidVar = getpid()
    var addr = HAL.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var size = UInt32(4)
    AudioObjectGetPropertyData(HAL.system, &addr, UInt32(MemoryLayout<pid_t>.size), &pidVar, &size, &myObj)

    let meter = AppTap(processIDs: [found.objectID], mode: .meter, outputUID: nil)
    try! meter.start()
    Thread.sleep(forTimeInterval: 0.6)
    let before = meter.peak
    print("source level before processing:", before, db(before))

    let tap = AppTap(processIDs: [found.objectID], mode: .process, outputUID: nil)
    tap.processor.params.update(volume: 0.25, muted: false, eq: Array(repeating: 0, count: 10), eqEnabled: true)
    do { try tap.start() } catch { print("FAIL start:", error.localizedDescription); exit(1) }

    let observer = AppTap(processIDs: [myObj], mode: .meter, outputUID: nil)
    if myObj != 0 { try? observer.start() }
    Thread.sleep(forTimeInterval: 1.2)
    print("engine reports output peak:", tap.peak, db(tap.peak))
    print("what really left this process:", observer.peak, db(observer.peak))
    check("live volume 25%", abs(tap.peak - before * 0.25) < 0.03, "\(before) x 0.25 = \(before * 0.25), engine says \(tap.peak)")
    if myObj != 0 { check("output reaches the device", abs(observer.peak - tap.peak) < 0.03, "device-side peak \(observer.peak)") }

    tap.processor.params.update(volume: 1, muted: true, eq: Array(repeating: 0, count: 10), eqEnabled: true)
    Thread.sleep(forTimeInterval: 0.8)
    check("live mute", tap.peak < 0.005, "peak \(tap.peak)")
    tap.stop(); meter.stop(); observer.stop()
}
player.terminate()
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
