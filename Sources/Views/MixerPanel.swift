import SwiftUI
import AppKit

struct MixerPanel: View {
    @Environment(MixerModel.self) private var model
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            header
            if let problem = model.problem { ProblemBanner(text: problem, dismiss: model.dismissProblem) }
            OutputCard()
            appsSection
        }
        .padding(14)
        .frame(width: 380)
        .background(WindowVisibility { model.isPanelVisible = $0 })
        .animation(.smooth(duration: 0.3), value: model.apps.map(\.id))
        .animation(.smooth(duration: 0.25), value: model.problem)
    }

    private var header: some View {
        HStack {
            Text("Levels").font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer()
            IconButton(symbol: "gearshape.fill", label: "Settings", action: openSettings)
            IconButton(symbol: "power", label: "Quit Levels") { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder private var appsSection: some View {
        if model.apps.isEmpty {
            EmptyApps()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("APPS")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 6)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.apps) { item in
                            AppRowView(item: item)
                                .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                                                        removal: .opacity))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 460)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OutputCard: View {
    @Environment(MixerModel.self) private var model
    private var current: OutputDevice? { model.outputs.first { $0.id == model.defaultOutputID } }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: current?.symbol ?? "hifispeaker")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Output").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(current?.name ?? "No output").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        .contentTransition(.interpolate)
                }
                Spacer()
                if model.outputs.count > 1 {
                    Menu {
                        ForEach(model.outputs) { d in
                            Button { model.chooseSystemOutput(d) } label: {
                                Label(d.name, systemImage: d.id == model.defaultOutputID ? "checkmark" : d.symbol)
                            }
                        }
                    } label: {
                        Text("Change").font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.button).buttonStyle(.glass).controlSize(.small).fixedSize()
                }
            }
            if model.defaultOutputID != 0, Devices.volume(model.defaultOutputID) != nil {
                CapsuleSlider(
                    value: Binding(get: { Double(model.systemVolume) }, set: { model.setSystemVolume(Float($0)) }),
                    symbol: { $0 < 0.005 ? "speaker.slash.fill" : "speaker.wave.3.fill" },
                    variable: { $0 },
                    tint: .secondary,
                    valueText: { "\(Int(($0 * 100).rounded()))%" },
                    accessibilityName: "Mac volume")
            }
        }
        .padding(12)
        .background(.primary.opacity(0.055), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.06)))
    }
}

struct EmptyApps: View {
    @State private var wave = 0
    var body: some View {
        VStack(spacing: 10) {
            // Once on appear, never looping: a repeating symbol effect costs ~20% CPU even when hidden.
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, options: .nonRepeating, value: wave)
                .onAppear { wave += 1 }
            Text("Nothing is playing").font(.system(size: 14, weight: .semibold))
            Text("Play music or a video in any app and it appears here. Then drag its slider to change its volume, or open it to shape the sound with the equalizer.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 22).padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 20, style: .continuous))
        .transition(.opacity)
    }
}

struct ProblemBanner: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings") { Permissions.openPrivacySettings() }
                    .buttonStyle(.glass).controlSize(.small)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.orange.opacity(0.14), in: .rect(cornerRadius: 16, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Tells the model whether the popover is on screen, so meters only run while someone is looking.
struct WindowVisibility: NSViewRepresentable {
    let changed: (Bool) -> Void
    func makeNSView(context: Context) -> NSView { Probe(changed) }
    func updateNSView(_ v: NSView, context: Context) {}

    final class Probe: NSView {
        let changed: (Bool) -> Void
        init(_ c: @escaping (Bool) -> Void) { changed = c; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            let nc = NotificationCenter.default
            for (name, value) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false),
                                  (NSWindow.willCloseNotification, false), (NSWindow.didChangeOcclusionStateNotification, true)] {
                nc.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                    guard let self, let w = self.window else { return }
                    self.changed(name == NSWindow.didChangeOcclusionStateNotification ? w.occlusionState.contains(.visible) : value)
                }
            }
            changed(w.isVisible)
        }
    }
}

enum Permissions {
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
