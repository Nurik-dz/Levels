import AppKit
import CoreGraphics

// Draws Levels' icon: three mixer faders on Apple's squircle. Usage: make_icon <out.png> [variant]
let variant = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "a"
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// Apple's squircle: a superellipse, n = 5, 824 tile on the 1024 canvas.
func squircle(in rect: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2, cx = rect.midX, cy = rect.midY
    for i in 0...360 {
        let t = CGFloat(i) * .pi / 180
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(in: tile)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0, 0, 0, 0.38))
ctx.addPath(shape); ctx.setFillColor(color(0.2, 0.3, 0.9)); ctx.fillPath()
ctx.restoreGState()

// Body gradient.
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let top: [CGFloat], bottom: [CGFloat]
switch variant {
case "b": top = [0.99, 0.55, 0.27]; bottom = [0.90, 0.20, 0.38]          // warm
default:  top = [0.36, 0.62, 1.00]; bottom = [0.36, 0.20, 0.92]          // blue to violet
}
let grad = CGGradient(colorsSpace: cs, colors: [color(top[0], top[1], top[2]), color(bottom[0], bottom[1], bottom[2])] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: S / 2, y: tile.maxY), end: CGPoint(x: S / 2, y: tile.minY), options: [])

// Soft light from the top.
let light = CGGradient(colorsSpace: cs, colors: [color(1, 1, 1, 0.34), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(light, startCenter: CGPoint(x: S / 2, y: tile.maxY + 40), startRadius: 0,
                       endCenter: CGPoint(x: S / 2, y: tile.maxY + 40), endRadius: 620, options: [])

// Three faders.
let trackW: CGFloat = 70, gap: CGFloat = 150
let trackH: CGFloat = 470
let baseY = (S - trackH) / 2 - 6
let levels: [CGFloat] = [0.34, 0.78, 0.55]
for i in 0..<3 {
    let x = S / 2 + CGFloat(i - 1) * (trackW + gap) - trackW / 2
    let track = CGRect(x: x, y: baseY, width: trackW, height: trackH)
    // track
    ctx.setFillColor(color(1, 1, 1, 0.30))
    ctx.addPath(CGPath(roundedRect: track, cornerWidth: trackW / 2, cornerHeight: trackW / 2, transform: nil)); ctx.fillPath()
    // fill up to the knob
    let ky = baseY + trackH * levels[i]
    let fill = CGRect(x: x, y: baseY, width: trackW, height: ky - baseY)
    ctx.setFillColor(color(1, 1, 1, 0.96))
    ctx.addPath(CGPath(roundedRect: fill, cornerWidth: trackW / 2, cornerHeight: trackW / 2, transform: nil)); ctx.fillPath()
    // knob, with its own shadow
    let kr: CGFloat = 70
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0.05, 0.05, 0.3, 0.45))
    ctx.setFillColor(color(1, 1, 1))
    ctx.fillEllipse(in: CGRect(x: x + trackW / 2 - kr, y: ky - kr, width: kr * 2, height: kr * 2))
    ctx.restoreGState()
    // a hint of glass on the knob
    ctx.setFillColor(color(0.55, 0.6, 0.95, 0.20))
    ctx.fillEllipse(in: CGRect(x: x + trackW / 2 - kr * 0.62, y: ky - kr * 0.62 - 6, width: kr * 1.24, height: kr * 1.24))
}
ctx.restoreGState()

// Fine rim.
ctx.saveGState()
ctx.addPath(shape); ctx.setLineWidth(3); ctx.setStrokeColor(color(1, 1, 1, 0.22)); ctx.strokePath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
