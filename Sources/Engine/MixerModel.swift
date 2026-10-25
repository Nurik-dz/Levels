import Foundation
import AppKit
import CoreAudio
import Observation

struct MixerApp: Identifiable {
    var id: String { app.bundleID }
    var app: AudioApp
    var settings: AppSettings
    var isPlaying: Bool { app.isPlaying }
}

/// What the panel lists: an app is a row only while it makes sound (plus a short grace so rows do not
/// flicker in the gap between two songs). Not playing means not there. Saved changes keep working in the
/// background and come back with the app; Settings lists them.
enum Visibility {
    static let grace: Double = 4          // seconds a row stays after its sound stops

    static func live(_ rows: [MixerApp], lastSound: [String: Double], now: Double) -> [MixerApp] {
        rows.filter { $0.isPlaying || now - (lastSound[$0.id] ?? -1e9) < grace }
            .sorted { a, b in
                if a.isPlaying != b.isPlaying { return a.isPlaying }
                return a.app.name.localizedCaseInsensitiveCompare(b.app.name) == .orderedAscending
            }
    }
}

/// The one object the interface watches. It decides, several times a second, which apps need a
/// live connection and keeps the engine in step with what the user chose.
@MainActor @Observable
final class MixerModel {
    /// Apps making sound now (or a moment ago).
    private(set) var apps: [MixerApp] = []
    private(set) var outputs: [OutputDevice] = []
    private(set) var defaultOutputID: AudioObjectID = 0
    private(set) var systemVolume: Float = 0
    private(set) var systemMuted = false
    private(set) var problem: String?

    /// Set by the popover so meters only run while someone is looking.
    var isPanelVisible = false { didSet { if isPanelVisible { refresh() } else { reconcile() } } }

    private var settings: [String: AppSettings] = [:]
    private var taps: [String: AppTap] = [:]
    private var names: [String: String] = [:]         // bundle ID -> name, so saved apps keep a label
    private var lastSound: [String: Double] = [:]     // bundle ID -> uptime when it last made sound
    private var timer: Timer?
    private var lastDefaultOutput: AudioObjectID = 0
    private var sampleMode = false
    private let store = UserDefaults.standard
    private static let key = "levels.settings.v1"
    private static let namesKey = "levels.names.v1"

    init() {
        if let data = store.data(forKey: Self.key),
           let s = try? JSONDecoder().decode([String: AppSettings].self, from: data) { settings = s }
        if let n = store.dictionary(forKey: Self.namesKey) as? [String: String] { names = n }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// For pictures and tests only: show these rows and stop reading the real Mac.
    func showSample(_ rows: [MixerApp], outputs sampleOutputs: [OutputDevice], defaultOutput: AudioObjectID) {
        sampleMode = true
        timer?.invalidate(); timer = nil
        shutdown()
        apps = rows; outputs = sampleOutputs; defaultOutputID = defaultOutput; systemVolume = 0.62
        for r in rows { settings[r.id] = r.settings; names[r.id] = r.app.name }
    }

    // MARK: Reading the Mac

    func refresh() {
        guard !sampleMode else { return }
        let found = Processes.apps()
        // A monotonic clock: the Mac's own clock can jump (time zone, network time).
        let now = ProcessInfo.processInfo.systemUptime
        for a in found where a.isPlaying { lastSound[a.bundleID] = now }
        let rows = found.map { MixerApp(app: $0, settings: settings[$0.bundleID] ?? AppSettings()) }
        let live = Visibility.live(rows, lastSound: lastSound, now: now)
        // Assign only what changed, so the interface is not redrawn twice a second for nothing.
        if live.map(\.id) != apps.map(\.id) || live.map(\.isPlaying) != apps.map(\.isPlaying) {
            apps = live
        } else {
            for i in apps.indices where apps[i].settings != live[i].settings { apps[i].settings = live[i].settings }
        }
        outputs = Devices.outputs()
        defaultOutputID = Devices.defaultOutputID() ?? 0
        if defaultOutputID != 0 {
            systemVolume = Devices.volume(defaultOutputID) ?? systemVolume
            systemMuted = Devices.isMuted(defaultOutputID)
        }
        var learned = false
        for r in found where names[r.bundleID] != r.name { names[r.bundleID] = r.name; learned = true }
        if learned { store.set(names, forKey: Self.namesKey) }
        reconcile(found: found)
    }

    // MARK: Changing things

    func settings(for id: String) -> AppSettings { settings[id] ?? AppSettings() }

    func change(_ id: String, _ edit: (inout AppSettings) -> Void) {
        var s = settings[id] ?? AppSettings()
        edit(&s)
        if s == AppSettings() { settings[id] = nil } else { settings[id] = s }
        if let i = apps.firstIndex(where: { $0.id == id }) { apps[i].settings = s }
        save()
        reconcile()
        taps[id]?.processor.params.update(volume: Float(s.volume), muted: s.muted, eq: s.eq, eqEnabled: s.eqEnabled)
    }

    func reset(_ id: String) { change(id) { $0 = AppSettings() } }

    /// Every app back to normal, including the ones that are not on screen or not running.
    func resetAll() {
        settings.removeAll()
        save()
        for i in apps.indices { apps[i].settings = AppSettings() }
        reconcile()
    }

    /// Every app with saved changes, running or not, for the Settings list.
    var remembered: [(id: String, name: String, summary: String)] {
        settings.compactMap { id, s in
            s.needsProcessing ? (id, names[id] ?? (id == Processes.callsID ? "FaceTime & Calls" : id), s.summary) : nil
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setSystemVolume(_ v: Float) {
        systemVolume = v
        if defaultOutputID != 0 { Devices.setVolume(defaultOutputID, v) }
    }

    func chooseSystemOutput(_ device: OutputDevice) {
        Devices.setDefaultOutput(device.id)
        defaultOutputID = device.id
        refresh()
    }

    func level(for id: String) -> Float { taps[id]?.peak ?? 0 }
    func hasLiveConnection(_ id: String) -> Bool { taps[id] != nil }
    func dismissProblem() { problem = nil }

    // MARK: Keeping the engine in step

    private func reconcile(found: [AudioApp]? = nil) {
        guard !sampleMode else { return }
        let current = found ?? Processes.apps()
        var wanted: [String: (ids: [AudioObjectID], mode: AppTap.Mode, uid: String?)] = [:]
        for a in current {
            let s = settings[a.bundleID] ?? AppSettings()
            if s.needsProcessing {
                wanted[a.bundleID] = (a.processIDs, .process, s.outputUID.flatMap(deviceExists))
            } else if isPanelVisible && a.isPlaying {
                wanted[a.bundleID] = (a.processIDs, .meter, nil)
            }
        }
        // The Mac switched speakers: connections that follow the Mac must follow it too.
        let followChanged = lastDefaultOutput != 0 && lastDefaultOutput != defaultOutputID
        lastDefaultOutput = defaultOutputID
        for (id, tap) in taps {
            if followChanged, tap.mode == .process, tap.outputUID == nil { tap.stop(); taps[id] = nil; continue }
            guard let w = wanted[id], w.mode == tap.mode, w.uid == tap.outputUID, w.ids == tap.processIDs else {
                tap.stop(); taps[id] = nil; continue
            }
        }
        for (id, w) in wanted where taps[id] == nil {
            let tap = AppTap(processIDs: w.ids, mode: w.mode, outputUID: w.uid)
            let s = settings[id] ?? AppSettings()
            tap.processor.params.update(volume: Float(s.volume), muted: s.muted, eq: s.eq, eqEnabled: s.eqEnabled)
            do { try tap.start(); taps[id] = tap; if problem != nil, w.mode == .process { problem = nil } }
            catch { problem = error.localizedDescription }
        }
    }

    private func deviceExists(_ uid: String) -> String? { outputs.contains { $0.uid == uid } ? uid : nil }

    private func save() {
        if let d = try? JSONEncoder().encode(settings) { store.set(d, forKey: Self.key) }
    }

    func shutdown() { taps.values.forEach { $0.stop() }; taps.removeAll() }
}
