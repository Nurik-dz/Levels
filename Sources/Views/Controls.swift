import SwiftUI
import AppKit

/// Control Center style slider: a capsule that fills, with the symbol and the value inside it.
struct CapsuleSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var symbol: (Double) -> String = { _ in "speaker.wave.3.fill" }
    var variable: ((Double) -> Double?)? = nil
    var tint: Color = .accentColor
    var detent: Double? = nil
    var valueText: (Double) -> String
    var accessibilityName: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false
    @State private var atDetent = false
    private let height: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let f = CGFloat((value - range.lowerBound) / span)
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.09))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(height, w * f))
                    .opacity(value <= range.lowerBound + 0.0001 ? 0.0 : 1)
                if let d = detent {
                    let x = w * CGFloat((d - range.lowerBound) / span)
                    Capsule().fill(.primary.opacity(0.28)).frame(width: 2, height: 10).offset(x: x - 1)
                }
                HStack(spacing: 6) {
                    Group {
                        if let v = variable?(value) {
                            Image(systemName: symbol(value), variableValue: v)
                        } else {
                            Image(systemName: symbol(value))
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .contentTransition(.symbolEffect(.replace))
                    Spacer(minLength: 0)
                    Text(valueText(value))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .foregroundStyle(f > 0.14 ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .allowsHitTesting(false)
            }
            .frame(height: height)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        var v = range.lowerBound + span * Double(min(1, max(0, g.location.x / w)))
                        if let d = detent, abs(v - d) < span * 0.025 {
                            v = d
                            if !atDetent { atDetent = true; NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                        } else { atDetent = false }
                        withAnimation(.snappy(duration: 0.12)) { value = v }
                    }
                    .onEnded { _ in dragging = false; onEditingChanged(false) }
            )
            .scaleEffect(dragging ? 1.015 : 1, anchor: .center)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: dragging)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(valueText(value))
        .accessibilityAdjustableAction { dir in
            let step = (range.upperBound - range.lowerBound) / 20
            switch dir {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

/// Four soft bars that dance with the app's real level, like the indicator in Music.
/// The height follows decibels (what the ear hears), not raw amplitude, so ordinary music fills it.
struct LevelMeter: View {
    let level: () -> Float
    var active: Bool
    @State private var held: Double = 0

    var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    let peak = Double(level())
                    let db = 20 * log10(max(peak, 0.00003))
                    let target = min(1, max(0, (db + 48) / 48))
                    bars(target: target, t: ctx.date.timeIntervalSinceReferenceDate)
                        .animation(.smooth(duration: 0.12), value: target)
                }
            } else {
                // At rest nothing ticks: a silent row costs no frames.
                bars(target: 0, t: 0)
            }
        }
        .animation(.smooth(duration: 0.2), value: active)
        .accessibilityHidden(true)
    }

    private func bars(target: Double, t: Double) -> some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                let wobble = 0.8 + 0.2 * sin(t * (6.0 + Double(i) * 2.1) + Double(i) * 1.3)
                let h = target > 0.02 ? 4 + 16 * target * wobble : 3
                Capsule()
                    .fill(target > 0.02 ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 3.5, height: h)
            }
        }
        .frame(width: 20, height: 20, alignment: .bottom)
    }
}

/// Round glass icon button used across the panel.
struct IconButton: View {
    let symbol: String
    let label: String
    var tint: Color? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(tint)
        .help(label)
        .accessibilityLabel(label)
    }
}
