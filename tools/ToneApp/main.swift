import AppKit
import AVFoundation

// A tiny regular app that plays a steady 440 Hz tone at amplitude 0.5, for testing Levels end to end.
let engine = AVAudioEngine()
var phase = 0.0
let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
let src = AVAudioSourceNode { _, _, frames, abl in
    let list = UnsafeMutableAudioBufferListPointer(abl)
    for f in 0..<Int(frames) {
        let v = Float(0.5 * sin(phase)); phase += 2 * .pi * 440 / rate
        for b in list { b.mData!.assumingMemoryBound(to: Float.self)[f] = v }
    }
    return noErr
}
engine.attach(src)
engine.connect(src, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
try! engine.start()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.run()
