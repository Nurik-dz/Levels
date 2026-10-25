import CoreAudio
import AudioToolbox
import Foundation

enum TapError: Error, LocalizedError {
    case tap(OSStatus), aggregate(OSStatus), ioProc(OSStatus), start(OSStatus), noOutput
    var errorDescription: String? {
        switch self {
        case .tap(let s): return "Could not listen to the app (\(s)). Allow Levels under System Settings > Privacy & Security > Screen & System Audio Recording."
        case .aggregate(let s): return "Could not prepare the sound path (\(s))."
        case .ioProc(let s): return "Could not start the sound processor (\(s))."
        case .start(let s): return "Could not start the sound path (\(s))."
        case .noOutput: return "No sound output device was found."
        }
    }
}

/// One live connection to one app's sound.
///  - `.meter`: listens only (the app keeps playing untouched) to draw its level.
///  - `.process`: takes the app's sound over, changes it, and plays it to a chosen device.
final class AppTap {
    enum Mode: Equatable { case meter, process }

    let processIDs: [AudioObjectID]
    let mode: Mode
    let outputUID: String?
    let processor = StereoProcessor(sampleRate: 48000)

    /// Latest block peak (0...1). Written by the audio thread, read by the UI.
    private let peakBox = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    var peak: Float { peakBox.pointee }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var running = false

    // Scratch, sized once so the audio thread never allocates.
    private static let capacity = 16384
    private let scratchL = UnsafeMutablePointer<Float>.allocate(capacity: AppTap.capacity)
    private let scratchR = UnsafeMutablePointer<Float>.allocate(capacity: AppTap.capacity)

    init(processIDs: [AudioObjectID], mode: Mode, outputUID: String?) {
        self.processIDs = processIDs
        self.mode = mode
        self.outputUID = outputUID
        peakBox.initialize(to: 0)
    }

    deinit {
        stop()
        peakBox.deallocate(); scratchL.deallocate(); scratchR.deallocate()
    }

    func start() throws {
        let desc = CATapDescription(stereoMixdownOfProcesses: processIDs)
        desc.uuid = UUID()
        desc.muteBehavior = mode == .process ? .mutedWhenTapped : .unmuted
        desc.isPrivate = true
        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else { throw TapError.tap(st) }

        var dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Levels",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        if mode == .process {
            guard let uid = outputUID ?? Devices.defaultOutputID().flatMap({ HAL.string($0, kAudioDevicePropertyDeviceUID) })
            else { stop(); throw TapError.noOutput }
            dict[kAudioAggregateDeviceMainSubDeviceKey] = uid
            dict[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: uid]]
        }
        st = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID)
        guard st == noErr else { stop(); throw TapError.aggregate(st) }

        if let rate = HAL.scalar(aggID, kAudioDevicePropertyNominalSampleRate, Float64(48000)) {
            processor.setSampleRate(rate)
        }
        let nonInterleavedIn = Self.isNonInterleaved(tapID)
        let processing = mode == .process
        let cap = Self.capacity
        let l = scratchL, r = scratchR, peakBox = self.peakBox, processor = self.processor

        st = AudioDeviceCreateIOProcIDWithBlock(&proc, aggID, nil) { _, inData, _, outData, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard input.count > 0 else { return }

            // 1. Read whatever layout the tap gives into two clean channels.
            var frames = 0
            if nonInterleavedIn && input.count >= 2 {
                frames = Int(input[0].mDataByteSize) / 4
                if let a = input[0].mData?.assumingMemoryBound(to: Float.self),
                   let b = input[1].mData?.assumingMemoryBound(to: Float.self) {
                    frames = min(frames, cap)
                    for i in 0..<frames { l[i] = a[i]; r[i] = b[i] }
                }
            } else if let p = input[0].mData?.assumingMemoryBound(to: Float.self) {
                let ch = max(1, Int(input[0].mNumberChannels))
                frames = min(Int(input[0].mDataByteSize) / (4 * ch), cap)
                for i in 0..<frames { l[i] = p[i * ch]; r[i] = p[i * ch + (ch > 1 ? 1 : 0)] }
            }
            guard frames > 0 else { return }

            if !processing {
                var pk: Float = 0
                for i in 0..<frames { pk = max(pk, abs(l[i]), abs(r[i])) }
                peakBox.pointee = pk
                return
            }

            // 2. Volume, mute and equaliser.
            peakBox.pointee = processor.process(l, r, frames: frames)

            // 3. Hand the result to the chosen output device.
            let out = UnsafeMutableAudioBufferListPointer(outData)
            for (k, buf) in out.enumerated() {
                guard let o = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let ch = max(1, Int(buf.mNumberChannels))
                let room = Int(buf.mDataByteSize) / (4 * ch)
                let n = min(frames, room)
                if ch == 1 && out.count > 1 {
                    let src = (k % 2 == 0) ? l : r
                    for i in 0..<n { o[i] = src[i] }
                } else {
                    for i in 0..<n {
                        o[i * ch] = l[i]
                        if ch > 1 { o[i * ch + 1] = r[i] }
                        if ch > 2 { for c in 2..<ch { o[i * ch + c] = 0 } }
                    }
                }
            }
        }
        guard st == noErr else { stop(); throw TapError.ioProc(st) }
        st = AudioDeviceStart(aggID, proc)
        guard st == noErr else { stop(); throw TapError.start(st) }
        running = true
    }

    func stop() {
        if running, let proc { AudioDeviceStop(aggID, proc) }
        if let proc, aggID != kAudioObjectUnknown { AudioDeviceDestroyIOProcID(aggID, proc) }
        proc = nil
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
        running = false
        peakBox.pointee = 0
    }

    private static func isNonInterleaved(_ tap: AudioObjectID) -> Bool {
        var a = HAL.address(kAudioTapPropertyFormat)
        var f = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &a, 0, nil, &size, &f) == noErr else { return false }
        return f.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
    }
}
