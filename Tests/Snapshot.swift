import SwiftUI
import AppKit

@MainActor func app(_ path: String, _ bid: String, playing: Bool, _ s: AppSettings = AppSettings()) -> MixerApp {
    let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    return MixerApp(app: AudioApp(bundleID: bid, name: name, icon: NSWorkspace.shared.icon(forFile: path),
                                  processIDs: [], isPlaying: playing), settings: s)
}

@MainActor func snapshot(_ view: some View, name: String, size: CGSize) {
    let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
    let win = NSWindow(contentRect: NSRect(x: -6000, y: 0, width: size.width, height: size.height),
                       styleMask: [.borderless], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: .aqua)
    win.contentView = host
    win.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    let fit = host.fittingSize
    win.setContentSize(NSSize(width: size.width, height: max(fit.height, 100)))
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    let out = CommandLine.arguments[1] + "/\(name).png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote", out, Int(host.bounds.width), "x", Int(host.bounds.height))
}

let appKit = NSApplication.shared
appKit.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    let model = MixerModel()
    var eq = AppSettings(); eq.volume = 0.7; eq.eq = [4, 3, 1, 0, -1, 0, 1, 3, 4, 3]
    var muted = AppSettings(); muted.muted = true
    var boosted = AppSettings(); boosted.volume = 1.25
    let outs = [OutputDevice(id: 1, uid: "a", name: "MacBook Pro Speakers", isBuiltIn: true),
                OutputDevice(id: 2, uid: "b", name: "Nurik's AirPods Pro", isBuiltIn: false)]
    model.showSample([
        app("/Applications/Safari.app", "com.apple.Safari", playing: true, eq),
        app("/Applications/Stalker Player.app", "com.nurik.stalkerplayer", playing: true, boosted),
    ], outputs: outs, defaultOutput: 1)
    snapshot(MixerPanel(openSettings: {}).environment(model), name: "panel", size: CGSize(width: 380, height: 700))

    snapshot(AppRowView(item: model.apps[0], startExpanded: true).environment(model).padding(14), name: "expanded", size: CGSize(width: 380, height: 500))
    let empty = MixerModel(); empty.showSample([], outputs: outs, defaultOutput: 2)
    snapshot(MixerPanel(openSettings: {}).environment(empty), name: "empty", size: CGSize(width: 380, height: 400))
    snapshot(WelcomeView(start: {}), name: "welcome", size: CGSize(width: 440, height: 600))
    snapshot(SettingsView().environment(model), name: "settings", size: CGSize(width: 460, height: 520))
}
