import SwiftUI
import AppKit

/// One vertical band: drag up for more of that pitch, down for less. Snaps to flat.
struct EQBandSlider: View {
    @Binding var gain: Float
    let label: String
    let enabled: Bool
    @State private var dragging = false
    @State private var atZero = false
    private let trackHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 6) {
            Text(gain == 0 ? "0" : String(format: "%+.0f", gain))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .frame(height: 11)
            GeometryReader { geo in
                let h = geo.size.height
                let lo = EQBands.range.lowerBound, hi = EQBands.range.upperBound
                let y = h * CGFloat(1 - (gain - lo) / (hi - lo))
                ZStack(alignment: .top) {
                    Capsule().fill(.primary.opacity(0.09)).frame(width: 6)
                    // fill from the centre line to the knob
                    let mid = h / 2
                    Capsule()
                        .fill((enabled ? Color.accentColor : Color.secondary).gradient)
                        .frame(width: 6, height: max(2, abs(y - mid)))
                        .offset(y: min(y, mid))
                    Capsule().fill(.primary.opacity(0.25)).frame(width: 12, height: 1.5).offset(y: mid - 0.75)
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.22), radius: dragging ? 4 : 2, y: 1)
                        .frame(width: dragging ? 17 : 15, height: dragging ? 17 : 15)
                        .offset(y: y - (dragging ? 8.5 : 7.5))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dragging = true
                            var v = hi - Float(min(1, max(0, g.location.y / h))) * (hi - lo)
                            if abs(v) < 0.8 {
                                v = 0
                                if !atZero { atZero = true; NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                            } else { atZero = false }
                            gain = (v * 2).rounded() / 2
                        }
                        .onEnded { _ in dragging = false }
                )
                .animation(.spring(duration: 0.22, bounce: 0.25), value: dragging)
            }
            .frame(height: trackHeight)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).frame(height: 11)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("\(label) hertz band")
        .accessibilityValue("\(Int(gain)) decibels")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: gain = min(EQBands.range.upperBound, gain + 1)
            case .decrement: gain = max(EQBands.range.lowerBound, gain - 1)
            @unknown default: break
            }
        }
    }
}

struct EqualizerView: View {
    let settings: AppSettings
    let edit: ((inout AppSettings) -> Void) -> Void

    private var currentPreset: EQPreset? {
        EQPreset.all.first { zip($0.gains, settings.eq).allSatisfy { abs($0 - $1) < 0.01 } }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("Equalizer", systemImage: "slider.vertical.3")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(EQPreset.all) { preset in
                        Button {
                            withAnimation(.smooth(duration: 0.3)) { edit { $0.eq = preset.gains; $0.eqEnabled = true } }
                        } label: {
                            Label(preset.name, systemImage: currentPreset == preset ? "checkmark" : preset.symbol)
                        }
                    }
                } label: {
                    Text(currentPreset?.name ?? "Custom")
                        .font(.system(size: 12, weight: .medium))
                        .contentTransition(.interpolate)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .controlSize(.small)
                .fixedSize()
                Toggle("Equalizer on", isOn: Binding(get: { settings.eqEnabled }, set: { v in edit { $0.eqEnabled = v } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            HStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { i in
                    EQBandSlider(
                        gain: Binding(get: { settings.eq[i] }, set: { v in edit { $0.eq[i] = v } }),
                        label: EQBands.labels[i], enabled: settings.eqEnabled)
                }
            }
            .opacity(settings.eqEnabled ? 1 : 0.45)
            .animation(.smooth(duration: 0.2), value: settings.eqEnabled)
        }
    }
}
