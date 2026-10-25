import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()
    private var welcome: NSWindow?
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        if !UserDefaults.standard.bool(forKey: "levels.welcomed") { showWelcome() }
    }

    func applicationWillTerminate(_ n: Notification) { model.shutdown() }

    func showWelcome() {
        let w = makeWindow(title: "Welcome to Levels", styleMask: [.titled, .closable, .fullSizeContentView]) {
            WelcomeView { [weak self] in
                UserDefaults.standard.set(true, forKey: "levels.welcomed")
                self?.welcome?.close()
            }
        }
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        welcome = w
        present(w)
    }

    func showSettings() {
        if let s = settings { present(s); return }
        let w = makeWindow(title: "Levels Settings", styleMask: [.titled, .closable]) {
            SettingsView().environment(self.model)
        }
        settings = w
        present(w)
    }

    private func makeWindow<V: View>(title: String, styleMask: NSWindow.StyleMask, @ViewBuilder _ content: () -> V) -> NSWindow {
        let host = NSHostingController(rootView: content())
        let w = NSWindow(contentViewController: host)
        w.title = title
        w.styleMask = styleMask
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }

    private func present(_ w: NSWindow) {
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}

@main
struct LevelsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MixerPanel(openSettings: { delegate.showSettings() })
                .environment(delegate.model)
        } label: {
            Image(systemName: "slider.vertical.3")
        }
        .menuBarExtraStyle(.window)
    }
}
