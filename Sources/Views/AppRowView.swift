import SwiftUI

struct AppRowView: View {
    @Environment(MixerModel.self) private var model
    let item: MixerApp
    @State private var expanded: Bool

    init(item: MixerApp, startExpanded: Bool = false) {
        self.item = item
        _expanded = State(initialValue: startExpanded)
    }

    private var s: AppSettings { item.settings }
    private var volumeBinding: Binding<Double> {
        Binding(get: { s.volume }, set: { v in model.change(item.id) { $0.volume = v; if v > 0 { $0.muted = false } } })
    }
    private var outputName: String {
        if let uid = s.outputUID, let d = model.outputs.first(where: { $0.uid == uid }) { return d.name }
        return model.outputs.first { $0.id == model.defaultOutputID }?.name ?? "This Mac"
    }
    /// One line that matches what is really happening to this app's sound right now.
    private var subtitle: String {
        if item.isPlaying {
            if s.muted { return "Playing, muted" }
            if s.volume < 0.005 { return "Playing, silenced" }
            return s.outputUID == nil ? "Playing" : "Playing to \(outputName)"
        }
        let extra = s.extras
        return extra.isEmpty ? "Not playing" : "Not playing · \(extra)"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    if let icon = item.app.icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "app.dashed").resizable().scaledToFit().padding(6).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                .saturation(item.isPlaying ? 1 : 0.4)
                .opacity(item.isPlaying ? 1 : 0.7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.interpolate)
                }
                Spacer(minLength: 4)
                LevelMeter(level: { model.level(for: item.id) }, active: item.isPlaying && !s.isSilenced)
                IconButton(symbol: s.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           label: s.muted ? "Unmute \(item.app.name)" : "Mute \(item.app.name)",
                           tint: s.muted ? .red : nil) {
                    model.change(item.id) { $0.muted.toggle() }
                }
                IconButton(symbol: "chevron.down", label: expanded ? "Hide options" : "Show options") {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { expanded.toggle() }
                }
                .rotationEffect(.degrees(expanded ? 180 : 0))
            }

            CapsuleSlider(
                value: volumeBinding, range: 0...1.5,
                symbol: { s.muted || $0 < 0.005 ? "speaker.slash.fill" : "speaker.wave.3.fill" },
                variable: { s.muted ? nil : min(1, $0) },
                tint: s.muted ? .gray : (s.volume > 1.0 ? .orange : .accentColor),
                detent: 1.0,
                valueText: { s.muted ? "Muted" : ($0 > 1.005 ? "Boost \(Int(($0 * 100).rounded()))%" : "\(Int(($0 * 100).rounded()))%") },
                accessibilityName: "\(item.app.name) volume")

            if expanded {
                VStack(spacing: 12) {
                    Divider().opacity(0.5)
                    EqualizerView(settings: s) { e in model.change(item.id, e) }
                    Divider().opacity(0.5)
                    HStack {
                        Menu {
                            Button { model.change(item.id) { $0.outputUID = nil } } label: {
                                Label("Follow the Mac", systemImage: s.outputUID == nil ? "checkmark" : "macbook")
                            }
                            Divider()
                            ForEach(model.outputs) { d in
                                Button { model.change(item.id) { $0.outputUID = d.uid } } label: {
                                    Label(d.name, systemImage: s.outputUID == d.uid ? "checkmark" : d.symbol)
                                }
                            }
                        } label: {
                            Label(s.outputUID == nil ? "Follow the Mac" : outputName, systemImage: "hifispeaker")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .menuStyle(.button).buttonStyle(.glass).controlSize(.small).fixedSize()
                        Spacer()
                        Button("Reset") { withAnimation(.smooth) { model.reset(item.id) } }
                            .buttonStyle(.glass).controlSize(.small)
                            .disabled(!s.needsProcessing)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(12)
        .background(.primary.opacity(0.055), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        .animation(.smooth(duration: 0.25), value: item.isPlaying)
    }
}
