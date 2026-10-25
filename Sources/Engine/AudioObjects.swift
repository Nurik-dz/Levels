import CoreAudio
import AudioToolbox
import AppKit

/// Small typed wrappers over the CoreAudio property API.
enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ sel: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func scalar<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ initial: T) -> T? {
        var a = address(sel, scope: scope)
        var v = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &v) { AudioObjectGetPropertyData(obj, &a, 0, nil, &size, $0) }
        return status == noErr ? v : nil
    }

    static func set<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ value: T) -> Bool {
        var a = address(sel, scope: scope)
        return withUnsafePointer(to: value) {
            AudioObjectSetPropertyData(obj, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        } == noErr
    }

    static func list(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var a = address(sel, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var a = address(sel, scope: scope)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ref) == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }
}

// MARK: - Output devices

struct OutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let isBuiltIn: Bool
    var symbol: String {
        let n = name.lowercased()
        if n.contains("airpods") { return "airpods" }
        if n.contains("headphone") || n.contains("buds") { return "headphones" }
        if n.contains("display") || n.contains("hdmi") || n.contains("tv") { return "tv" }
        if isBuiltIn { return "laptopcomputer" }
        return "hifispeaker"
    }
}

enum Devices {
    static func outputs() -> [OutputDevice] {
        HAL.list(HAL.system, kAudioHardwarePropertyDevices).compactMap { id in
            let streams = HAL.list(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            guard !streams.isEmpty,
                  let uid = HAL.string(id, kAudioDevicePropertyDeviceUID),
                  let name = HAL.string(id, kAudioObjectPropertyName) else { return nil }
            // Skip our own private aggregate devices and other hidden ones.
            if HAL.scalar(id, kAudioDevicePropertyIsHidden, UInt32(0)) == 1 { return nil }
            let transport = HAL.scalar(id, kAudioDevicePropertyTransportType, UInt32(0)) ?? 0
            if transport == kAudioDeviceTransportTypeAggregate || transport == kAudioDeviceTransportTypeVirtual { return nil }
            return OutputDevice(id: id, uid: uid, name: name, isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn)
        }
    }

    static func defaultOutputID() -> AudioObjectID? {
        HAL.scalar(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0))
    }

    static func setDefaultOutput(_ id: AudioObjectID) {
        _ = HAL.set(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, id)
    }

    /// 0...1 system volume of a device, nil if the device has no volume control.
    static func volume(_ id: AudioObjectID) -> Float? {
        HAL.scalar(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                   scope: kAudioObjectPropertyScopeOutput, Float32(0))
    }

    static func setVolume(_ id: AudioObjectID, _ v: Float) {
        _ = HAL.set(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                    scope: kAudioObjectPropertyScopeOutput, Float32(max(0, min(1, v))))
    }

    static func isMuted(_ id: AudioObjectID) -> Bool {
        (HAL.scalar(id, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, UInt32(0)) ?? 0) == 1
    }
}

// MARK: - Audio processes grouped into apps

struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
}

/// One thing the user recognises: Safari, Spotify, Brave (with all its helper processes).
struct AudioApp: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage?
    let processIDs: [AudioObjectID]
    let isPlaying: Bool
}

enum Processes {
    static func all() -> [AudioProcess] {
        HAL.list(HAL.system, kAudioHardwarePropertyProcessObjectList).compactMap { id in
            guard let pid = HAL.scalar(id, kAudioProcessPropertyPID, pid_t(0)) else { return nil }
            let out = HAL.scalar(id, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0
            return AudioProcess(objectID: id, pid: pid, bundleID: HAL.string(id, kAudioProcessPropertyBundleID),
                                isRunningOutput: out == 1)
        }
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let p = info.kp_eproc.e_ppid
        return p > 1 ? p : nil
    }

    /// Walks up from a helper process to the app the user launched.
    static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var cur: pid_t? = pid
        var hops = 0
        while let p = cur, hops < 6 {
            if let app = NSRunningApplication(processIdentifier: p),
               app.activationPolicy == .regular, app.bundleIdentifier != nil { return app }
            cur = parentPID(of: p)
            hops += 1
        }
        return nil
    }

    /// Calls are played by Apple background services, not by an app, so they get their own row.
    static let callServices: Set<String> = ["com.apple.avconferenced", "com.apple.TelephonyUtilities"]
    static let callsID = "system.calls"

    private static func callsIcon() -> NSImage? {
        for bid in ["com.apple.FaceTime", "com.apple.mobilephone"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return NSImage(systemSymbolName: "phone.circle.fill", accessibilityDescription: "Calls")
    }

    /// Everything currently registered with the audio system, grouped by app.
    /// Other system daemons (no app behind them) are left out; call services are one "FaceTime & Calls" row.
    static func apps(excluding own: String? = Bundle.main.bundleIdentifier) -> [AudioApp] {
        var groups: [String: (app: NSRunningApplication, ids: [AudioObjectID], playing: Bool)] = [:]
        var calls: (ids: [AudioObjectID], playing: Bool) = ([], false)
        for p in all() {
            if let app = owningApp(of: p.pid), let bid = app.bundleIdentifier {
                guard bid != own else { continue }
                var g = groups[bid] ?? (app, [], false)
                g.ids.append(p.objectID)
                g.playing = g.playing || p.isRunningOutput
                groups[bid] = g
            } else if let bid = p.bundleID, callServices.contains(bid) {
                calls.ids.append(p.objectID)
                calls.playing = calls.playing || p.isRunningOutput
            }
        }
        var result = groups.map { bid, g in
            AudioApp(bundleID: bid, name: g.app.localizedName ?? bid, icon: g.app.icon,
                     processIDs: g.ids.sorted(), isPlaying: g.playing)
        }
        if !calls.ids.isEmpty {
            result.append(AudioApp(bundleID: callsID, name: "FaceTime & Calls", icon: callsIcon(),
                                   processIDs: calls.ids.sorted(), isPlaying: calls.playing))
        }
        return result
    }
}
