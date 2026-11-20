// SPDX-License-Identifier: GPL-3.0-only
// The panel, drawn: a still layer (the panel, its lines and lettering, the knobs' scales and caps, the jacks, the
// keyboard) drawn once for a size, and a moving layer over it (pointers, lamps, cables, the key down, the wheel).
import SwiftUI
import FlatLink
#if canImport(AppKit)
import AppKit
#endif

public struct PanelView: View {
    let model: PanelModel
    public init(model: PanelModel) { self.model = model }

    public var body: some View {
        let f = model.frame
        return GeometryReader { geo in
            ZStack {
                Canvas(rendersAsynchronously: true) { ctx, size in
                    fit(&ctx, size)
                    Still.draw(&ctx)
                }
                Canvas { ctx, size in
                    fit(&ctx, size)
                    Moving.draw(&ctx, f)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let q = toPanel(p, geo.size)
                    model.pointerMoved(q)
                    #if canImport(AppKit)
                    (model.canPatch && model.hover != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
                    #endif
                case .ended: model.pointerMoved(nil)
                }
            }
            .gesture(SpatialTapGesture().onEnded { v in
                #if canImport(AppKit)
                let option = NSEvent.modifierFlags.contains(.option)
                #else
                let option = false
                #endif
                model.click(at: toPanel(v.location, geo.size), option: option)
            })
        }
        .aspectRatio(Geometry.size.width / Geometry.size.height, contentMode: .fit)
        .background(Palette.room)
    }

    /// a point in the view -> panel units (the inverse of fit)
    func toPanel(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        let s = min(size.width / Geometry.size.width, size.height / Geometry.size.height)
        let ox = (size.width - Geometry.size.width * s) / 2, oy = (size.height - Geometry.size.height * s) / 2
        return CGPoint(x: (p.x - ox) / s, y: (p.y - oy) / s)
    }

    func fit(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let s = min(size.width / Geometry.size.width, size.height / Geometry.size.height)
        ctx.translateBy(x: (size.width - Geometry.size.width * s) / 2, y: (size.height - Geometry.size.height * s) / 2)
        ctx.scaleBy(x: s, y: s)
    }
}

enum Palette {
    static let room = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let panel = Color(red: 0.125, green: 0.122, blue: 0.118)
    static let panelLow = Color(red: 0.105, green: 0.102, blue: 0.10)
    static let patch = Color(red: 0.085, green: 0.085, blue: 0.088)
    static let ink = Color(white: 0.86)
    static let inkDim = Color(white: 0.62)
    static let line = Color(white: 0.80).opacity(0.75)
    static let cables: [Color] = [
        Color(red: 0.95, green: 0.78, blue: 0.12), Color(red: 0.85, green: 0.25, blue: 0.18),
        Color(red: 0.18, green: 0.48, blue: 0.85), Color(red: 0.25, green: 0.68, blue: 0.31),
        Color(red: 0.93, green: 0.54, blue: 0.14), Color(red: 0.60, green: 0.36, blue: 0.83),
        Color(red: 0.17, green: 0.73, blue: 0.77), Color(red: 0.91, green: 0.91, blue: 0.87),
    ]
    static let lampOn = Color(red: 1.0, green: 0.16, blue: 0.10)
}

// ---- small drawing helpers
extension GraphicsContext {
    func text(_ s: String, _ p: CGPoint, size: CGFloat = 8, weight: Font.Weight = .medium, color: Color = Palette.ink,
              anchor: UnitPoint = .center) {
        draw(Text(s).font(.system(size: size, weight: weight).width(.condensed)).foregroundColor(color), at: p, anchor: anchor)
    }
    func circle(_ c: CGPoint, _ r: CGFloat, _ shading: Shading) {
        fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: shading)
    }
    func ring(_ c: CGPoint, _ r: CGFloat, _ color: Color, _ w: CGFloat) {
        stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color), lineWidth: w)
    }
    func line(_ a: CGPoint, _ b: CGPoint, _ color: Color = Palette.line, _ w: CGFloat = 1.2) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        stroke(p, with: .color(color), lineWidth: w)
    }
}

func polar(_ c: CGPoint, _ r: CGFloat, _ deg: Double) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a)))
}

// ---- the still layer
enum Still {
    static func draw(_ ctx: inout GraphicsContext) {
        panel(&ctx)
        for k in Layout.knobs { knob(&ctx, k) }
        diagram(&ctx)
        strip(&ctx)
        for j in Layout.jacks { jack(&ctx, j) }
        for l in Layout.lamps { ctx.circle(l.center, 5, .color(Color(white: 0.05))); ctx.circle(l.center, 3.5, .color(Color(red: 0.25, green: 0.05, blue: 0.04))) }
        keyboard(&ctx)
    }

    static func panel(_ ctx: inout GraphicsContext) {
        let r = Geometry.panel
        ctx.fill(Path(roundedRect: r, cornerRadius: 10),
                 with: .linearGradient(Gradient(colors: [Palette.panel, Palette.panelLow]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: r.height)))
        // the patch panel is black
        let px = P(898, 0).x
        ctx.fill(Path(roundedRect: CGRect(x: px, y: 0, width: r.width - px, height: r.height), cornerRadius: 10), with: .color(Palette.patch))
        ctx.fill(Path(CGRect(x: px, y: 0, width: 12, height: r.height)), with: .color(Palette.patch))
        // a few screws
        for p in [CGPoint(x: 18, y: 18), CGPoint(x: 18, y: r.height - 18), CGPoint(x: r.width - 18, y: r.height - 40)] {
            ctx.circle(p, 5, .radialGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.18)]), center: p, startRadius: 0, endRadius: 6))
            ctx.line(CGPoint(x: p.x - 3, y: p.y - 3), CGPoint(x: p.x + 3, y: p.y + 3), Color(white: 0.1), 1.2)
        }
        // the sections' lines: true verticals and horizontals, on the columns' boundaries
        let L: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (130, 21, 130, 382), (130, 394, 130, 510), (12, 388, 248, 388), (248, 21, 248, 510),
            (356, 21, 356, 284), (356, 297, 356, 510), (464, 21, 464, 284), (464, 297, 464, 510), (248, 290.7, 573, 290.7),
            (573, 21, 573, 510), (573, 193.3, 792, 193.3), (792, 21, 792, 510), (682, 201, 682, 510),
        ]
        for l in L { ctx.line(U(l.0, l.1), U(l.2, l.3), Palette.line, 1.3) }
        // the trimmers' holes
        for h in Layout.holes {
            ctx.circle(h, 6.5, .radialGradient(Gradient(colors: [Color(white: 0.02), Color(white: 0.16)]), center: h, startRadius: 2, endRadius: 7))
            ctx.ring(h, 6.5, Color(white: 0.30).opacity(0.7), 0.8)
        }
        // headings
        let H: [(String, CGFloat, CGFloat)] = [
            ("VOLTAGE CONTROLLED\nOSCILLATOR 1", Col.vco1, 32), ("VOLTAGE CONTROLLED\nOSCILLATOR 2", Col.vco2, 32), ("VCO MIXER", Col.mix, 28),
            ("VOLTAGE CONTROLLED\nHIGHPASS FILTER", Col.hpf, 32), ("VOLTAGE CONTROLLED\nLOWPASS FILTER", Col.lpf, 32),
            ("VOLTAGE CONTROLLED AMPLIFIER", 682.5, 28), ("ENVELOPE\nGENERATOR 2", Col.eg2, 34),
            ("PORTAMENTO", 71, 402), ("MASTER TUNE", 189, 402),
            ("FREQUENCY\nMODULATION", Col.mix, 312), ("CUTOFF FREQUENCY\nMODULATION", Col.hpf, 312), ("CUTOFF FREQUENCY\nMODULATION", Col.lpf, 312),
            ("MODULATION\nGENERATOR", Col.mg, 215), ("ENVELOPE\nGENERATOR 1", Col.eg1, 215),
        ]
        for h in H {
            let small = h.0.hasSuffix("MODULATION")       // (the modulation boxes' names are printed smaller)
            ctx.draw(Text(h.0).font(.system(size: small ? 7.4 : 8.6, weight: .regular)).foregroundColor(Palette.ink),
                     at: U(h.1, h.2), anchor: .center)
        }
        // the VCA: a triangle with EG 2 & EXT under it
        let c = U(682.5, 108)
        var t = Path()
        t.move(to: CGPoint(x: c.x - 24, y: c.y - 19)); t.addLine(to: CGPoint(x: c.x + 24, y: c.y)); t.addLine(to: CGPoint(x: c.x - 24, y: c.y + 19)); t.closeSubpath()
        ctx.stroke(t, with: .color(Palette.line), lineWidth: 1.2)
        ctx.line(CGPoint(x: c.x - 72, y: c.y), CGPoint(x: c.x - 24, y: c.y))
        ctx.line(CGPoint(x: c.x + 24, y: c.y), CGPoint(x: c.x + 64, y: c.y))
        ctx.line(CGPoint(x: c.x, y: c.y + 10), CGPoint(x: c.x, y: c.y + 46))
        ctx.text("EG 2 & EXT", CGPoint(x: c.x, y: c.y + 55), size: 7.5)
        // in the maker's place: this program's name
        ctx.text("FLAT-20", P(1398, 455), size: 30, weight: .heavy, color: Color(white: 0.9))
        ctx.text("after the MS-20 · for the FM-1", P(1398, 487), size: 9, weight: .regular, color: Palette.inkDim)
    }

    static func knob(_ ctx: inout GraphicsContext, _ k: KnobSpot) {
        let c = k.center, r = k.size.diameter / 2
        let tick0 = r + 1.5, tick1 = r + 4.5, num = r + (k.size == .standard ? 8.5 : 12.5)
        // the scale: a tick for each of 0 ... 10, and its number (or the switch's marks, or PW's and the MG's pictures)
        switch k.kind {
        case .dial, .bipolar, .pw, .mgWave:
            for i in 0...10 {
                let a = -150.0 + 30.0 * Double(i)
                ctx.line(polar(c, tick0, a), polar(c, tick1, a), Palette.ink, 1.0)
                switch k.kind {
                case .dial: ctx.text("\(i)", polar(c, num, a), size: k.size == .standard ? 5.8 : 7.0, weight: .regular, color: Palette.ink)
                case .bipolar:
                    ctx.text(i == 5 ? "0" : i < 5 ? "−\(5 - i)" : "+\(i - 5)", polar(c, num + 1.5, a), size: 5.8, weight: .regular, color: Palette.ink)
                default: break
                }
            }
            // PW's and the MG's pictures: one over the knob, the others on its name's line, either side of the name
            let lab = CGPoint(x: c.x, y: c.y + k.size.labelDrop)
            if case .pw = k.kind {
                Still.drawMark(&ctx, .pulse, polar(c, num + 2, 0))
                Still.drawMark(&ctx, .square, lab + CGPoint(x: -21, y: 0))
                ctx.line(lab + CGPoint(x: 15, y: 0), lab + CGPoint(x: 27, y: 0), Palette.ink, 1.1)
            }
            if case .mgWave = k.kind {
                Still.drawMark(&ctx, .square, polar(c, num + 14, 0))
                Still.drawMark(&ctx, .triangle, polar(c, num + 2.5, 0))
                Still.drawMark(&ctx, .pulse, lab + CGPoint(x: -42, y: 0))
                Still.drawMark(&ctx, .sawtooth, lab + CGPoint(x: -29, y: 0))
                Still.drawMark(&ctx, .ramp, lab + CGPoint(x: 29, y: 0))
                Still.drawMark(&ctx, .narrow, lab + CGPoint(x: 42, y: 0))
            }
        case .rotary(let marks, let mr):
            for (i, m) in marks.enumerated() {
                let a = Layout.switchAngles[i]
                ctx.line(polar(c, tick0, a), polar(c, mr - 10, a), Palette.ink, 1.0)
                Still.drawMark(&ctx, m, polar(c, mr, a))
            }
        }
        if !k.label.isEmpty { ctx.text(k.label, CGPoint(x: c.x, y: c.y + k.size.labelDrop), size: 7.5, weight: .regular) }
        // the knob, seen from the front: a fluted skirt, a domed cap on it
        ctx.circle(CGPoint(x: c.x + 2.5, y: c.y + 4), r + 1, .color(.black.opacity(0.5)))
        ctx.circle(c, r, .radialGradient(Gradient(colors: [Color(white: 0.17), Color(white: 0.035)]), center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.45), startRadius: 0, endRadius: r * 1.5))
        let flutes = k.size == .standard ? 22 : 28, cap = r * 0.78
        for i in 0..<flutes {
            let a = Double(i) * 360 / Double(flutes)
            // light catches the flutes on the upper left, as from a lamp above the player
            let lit = max(0, cos((a + 45) * .pi / 180))
            ctx.line(polar(c, cap + 1, a), polar(c, r - 1.2, a), Color(white: 0.30 + 0.45 * lit).opacity(0.25 + 0.55 * lit), r > 30 ? 2.2 : 1.8)
        }
        ctx.ring(c, r - 0.6, Color(white: 0.32).opacity(0.7), 1.0)
        ctx.circle(CGPoint(x: c.x + 1, y: c.y + 2), cap + 0.8, .color(.black.opacity(0.55)))
        ctx.circle(c, cap, .radialGradient(Gradient(colors: [Color(white: 0.30), Color(white: 0.10), Color(white: 0.04)]), center: CGPoint(x: c.x - cap * 0.4, y: c.y - cap * 0.45), startRadius: 0, endRadius: cap * 1.5))
        ctx.ring(c, cap, Color(white: 0.0).opacity(0.6), 0.8)
    }

    static func drawMark(_ ctx: inout GraphicsContext, _ m: SwitchMark, _ p: CGPoint) {
        let w: CGFloat = 6, h: CGFloat = 4.5
        var s = Path()
        switch m {
        case .text(let t): ctx.text(t, p, size: 8.5, weight: .regular); return
        case .ring: ctx.text("RING", p, size: 7.5, weight: .regular); return
        case .pwPulse:
            // a pulse, a two-way arrow, a narrow pulse
            for (dx, nw) in [(-10.0, 1.0), (10.0, 0.45)] as [(CGFloat, CGFloat)] {
                let q = CGPoint(x: p.x + dx, y: p.y), ww = 4.5 * nw
                s.move(to: CGPoint(x: q.x - 4.5, y: q.y + h)); s.addLine(to: CGPoint(x: q.x - 4.5, y: q.y - h))
                s.addLine(to: CGPoint(x: q.x - 4.5 + ww * 2 - 1, y: q.y - h)); s.addLine(to: CGPoint(x: q.x - 4.5 + ww * 2 - 1, y: q.y + h)); s.addLine(to: CGPoint(x: q.x + 4.5, y: q.y + h))
            }
            s.move(to: CGPoint(x: p.x - 4, y: p.y)); s.addLine(to: CGPoint(x: p.x + 4, y: p.y))
            s.move(to: CGPoint(x: p.x - 4, y: p.y)); s.addLine(to: CGPoint(x: p.x - 2.3, y: p.y - 1.5)); s.move(to: CGPoint(x: p.x - 4, y: p.y)); s.addLine(to: CGPoint(x: p.x - 2.3, y: p.y + 1.5))
            s.move(to: CGPoint(x: p.x + 4, y: p.y)); s.addLine(to: CGPoint(x: p.x + 2.3, y: p.y - 1.5)); s.move(to: CGPoint(x: p.x + 4, y: p.y)); s.addLine(to: CGPoint(x: p.x + 2.3, y: p.y + 1.5))
        case .ramp:
            s.move(to: CGPoint(x: p.x - w, y: p.y + h)); s.addLine(to: CGPoint(x: p.x + w, y: p.y - h)); s.addLine(to: CGPoint(x: p.x + w, y: p.y + h))
        case .narrow:
            s.move(to: CGPoint(x: p.x - w, y: p.y + h)); s.addLine(to: CGPoint(x: p.x - w * 0.6, y: p.y + h)); s.addLine(to: CGPoint(x: p.x - w * 0.6, y: p.y - h))
            s.addLine(to: CGPoint(x: p.x - w * 0.2, y: p.y - h)); s.addLine(to: CGPoint(x: p.x - w * 0.2, y: p.y + h)); s.addLine(to: CGPoint(x: p.x + w, y: p.y + h))
        case .triangle:
            s.move(to: CGPoint(x: p.x - w, y: p.y + h)); s.addLine(to: CGPoint(x: p.x, y: p.y - h)); s.addLine(to: CGPoint(x: p.x + w, y: p.y + h))
        case .sawtooth:
            s.move(to: CGPoint(x: p.x - w, y: p.y + h)); s.addLine(to: CGPoint(x: p.x - w, y: p.y - h)); s.addLine(to: CGPoint(x: p.x + w, y: p.y + h))
        case .square, .pulse:
            let f: CGFloat = m == .square ? 0 : -w * 0.55
            s.move(to: CGPoint(x: p.x - w, y: p.y + h)); s.addLine(to: CGPoint(x: p.x - w, y: p.y - h))
            s.addLine(to: CGPoint(x: p.x + f, y: p.y - h)); s.addLine(to: CGPoint(x: p.x + f, y: p.y + h)); s.addLine(to: CGPoint(x: p.x + w, y: p.y + h))
        case .noise:
            let ys: [CGFloat] = [0, -h, h * 0.6, -h * 0.4, h, -h * 0.8, h * 0.3, 0]
            for (i, y) in ys.enumerated() {
                let q = CGPoint(x: p.x - w + CGFloat(i) * 2 * w / CGFloat(ys.count - 1), y: p.y + y)
                if i == 0 { s.move(to: q) } else { s.addLine(to: q) }
            }
        }
        ctx.stroke(s, with: .color(Palette.ink), lineWidth: 1.1)
    }

    static func jack(_ ctx: inout GraphicsContext, _ j: JackSpot) {
        let c = j.center
        if !j.label.isEmpty {
            switch j.place {
            case .above: ctx.text(j.label, CGPoint(x: c.x, y: c.y - 24), size: 7.5, weight: .medium)
            case .below: ctx.text(j.label, CGPoint(x: c.x, y: c.y + 24), size: 7.5, weight: .medium)
            case .right: ctx.text(j.label, CGPoint(x: c.x + 19, y: c.y), size: 7.5, weight: .medium, anchor: .leading)
            case .at(let dx, let dy): ctx.text(j.label, CGPoint(x: c.x + dx, y: c.y + dy), size: 7.5, weight: .medium)
            }
        }
        if let l = j.legend {
            if l == "GND" {                     // a trigger: +5 V, to ground while on
                let o = CGPoint(x: c.x + 12, y: c.y + 20)
                var g = Path()
                g.move(to: CGPoint(x: o.x, y: o.y - 4)); g.addLine(to: CGPoint(x: o.x + 5, y: o.y - 4)); g.addLine(to: CGPoint(x: o.x + 5, y: o.y + 3)); g.addLine(to: CGPoint(x: o.x + 10, y: o.y + 3))
                ctx.stroke(g, with: .color(Palette.inkDim), lineWidth: 0.9)
                ctx.text("GND", CGPoint(x: o.x + 12, y: o.y + 3), size: 6.5, weight: .regular, color: Palette.inkDim, anchor: .leading)
            } else if let o = j.legendAt {
                ctx.text(l, CGPoint(x: c.x + o.x, y: c.y + o.y), size: 7, weight: .regular, color: Palette.inkDim,
                         anchor: o.x < 0 ? .trailing : o.x > 0 ? .leading : .center)
            } else {
                ctx.text(l, CGPoint(x: c.x, y: c.y + 24), size: 7, weight: .regular, color: Palette.inkDim)
            }
        }
        // a hex nut, a ring, the hole
        var hex = Path()
        for i in 0..<6 {
            let q = polar(c, 15, Double(i) * 60 + 30)
            if i == 0 { hex.move(to: q) } else { hex.addLine(to: q) }
        }
        hex.closeSubpath()
        ctx.fill(hex, with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.45)]), startPoint: CGPoint(x: c.x - 12, y: c.y - 12), endPoint: CGPoint(x: c.x + 12, y: c.y + 12)))
        ctx.circle(c, 10.5, .linearGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.92)]), startPoint: CGPoint(x: c.x - 8, y: c.y - 8), endPoint: CGPoint(x: c.x + 8, y: c.y + 8)))
        ctx.circle(c, 6, .color(Color(white: 0.04)))
    }

    /// The patch panel's diagram: a box for each block, and an arrow for every connection the circuit makes by
    /// itself, in the direction the signal goes. An arrow into an input jack is what that input carries with
    /// nothing plugged in (a plug breaks it); an arrow out of an input jack is where that input goes. The connections
    /// are the service manual's (docs/MS20-CIRCUIT.md); how the lines are routed is this drawing's own.
    static func diagram(_ ctx: inout GraphicsContext) {
        func box(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ s: String, _ h: CGFloat = 26) {
            let a = P(x0, y), b = P(x1, y)
            let r = CGRect(x: a.x, y: a.y - h / 2, width: b.x - a.x, height: h)
            ctx.fill(Path(r), with: .color(Palette.patch))
            ctx.stroke(Path(r), with: .color(Palette.line), lineWidth: 1.1)
            ctx.draw(Text(s).font(.system(size: 6.8, weight: .medium).width(.condensed)).foregroundColor(Palette.ink), at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
        }
        func tri(_ x: CGFloat, _ y: CGFloat, _ s: String) {
            let c = P(x, y); var t = Path()
            t.move(to: CGPoint(x: c.x - 11, y: c.y - 10)); t.addLine(to: CGPoint(x: c.x + 13, y: c.y)); t.addLine(to: CGPoint(x: c.x - 11, y: c.y + 10)); t.closeSubpath()
            ctx.fill(t, with: .color(Palette.patch)); ctx.stroke(t, with: .color(Palette.line), lineWidth: 1.1)
            ctx.text(s, CGPoint(x: c.x - 2, y: c.y), size: 5.5, weight: .semibold)
        }
        /// a line through photograph points, with an arrowhead at its end
        func arrow(_ pts: [(CGFloat, CGFloat)], head: Bool = true) {
            let q = pts.map { P($0.0, $0.1) }
            var p = Path(); p.move(to: q[0]); for x in q.dropFirst() { p.addLine(to: x) }
            ctx.stroke(p, with: .color(Palette.line), style: StrokeStyle(lineWidth: 1.1, lineCap: .butt, lineJoin: .miter))
            guard head, q.count >= 2 else { return }
            let e = q[q.count - 1], f = q[q.count - 2], d = hypot(e.x - f.x, e.y - f.y)
            guard d > 0 else { return }
            let ux = (e.x - f.x) / d, uy = (e.y - f.y) / d, s: CGFloat = 5.5
            var h = Path()
            h.move(to: e)
            h.addLine(to: CGPoint(x: e.x - ux * s - uy * s * 0.55, y: e.y - uy * s + ux * s * 0.55))
            h.addLine(to: CGPoint(x: e.x - ux * s + uy * s * 0.55, y: e.y - uy * s - ux * s * 0.55))
            h.closeSubpath()
            ctx.fill(h, with: .color(Palette.ink))
        }
        func dot(_ x: CGFloat, _ y: CGFloat) { ctx.circle(P(x, y), 2.2, .color(Palette.ink)) }

        // ---- the voice, along the top: both VCOs into the mixer (VCO 1 over VCO 2), mixer -> HPF -> LPF -> VCA -> VOLUME -> SIGNAL OUT
        arrow([(985, 70), (993, 70), (993, 54), (1072, 54), (1072, 68), (1082, 68)])
        arrow([(1065, 80), (1082, 80)]); arrow([(1112, 75), (1135, 75)])
        arrow([(1190, 75), (1210, 75)]); arrow([(1265, 75), (1280, 75)]); arrow([(1340, 75), (1358, 75)])
        arrow([(1450, 88), (1485, 88)])                                     // VOLUME -> SIGNAL OUT
        box(925, 985, 75, "VOLTAGE\nCONTROLLED\nOSCILLATOR 1", 30); box(1000, 1065, 75, "VOLTAGE\nCONTROLLED\nOSCILLATOR 2", 30)
        box(1082, 1112, 75, "VCO\nMIXER", 30); box(1135, 1190, 75, "VOLTAGE\nCONTROLLED\nHP FILTER", 30)
        box(1210, 1265, 75, "VOLTAGE\nCONTROLLED\nLP FILTER", 30); box(1280, 1340, 75, "VOLTAGE\nCONTROLLED\nAMPLIFIER", 30)
        // TOTAL: a line under the blocks into both VCOs (with FREQ) and both filters (with their CUTOFF FREQ inputs)
        arrow([(918, 104), (918, 97), (1225, 97)], head: false)
        arrow([(942, 113), (942, 104), (918, 104)], head: false)
        arrow([(955, 105), (955, 90)]); dot(955, 97)
        arrow([(1025, 113), (1025, 90)]); dot(1025, 97)
        arrow([(1025, 105), (955, 105)], head: false); dot(1025, 105); dot(955, 105)
        arrow([(1153, 113), (1153, 90)]); dot(1153, 97)
        arrow([(1225, 113), (1225, 90)]); dot(1225, 97)
        // EXT SIGNAL IN: into the high-pass filter, beside the mixer's output
        arrow([(1090, 113), (1090, 106), (1124, 106), (1124, 84), (1135, 84)])
        // INITIAL GAIN: the VCA (EG 2 joins it below)
        arrow([(1300, 113), (1300, 90)])

        // ---- the modulation generator: its two outputs, and its triangle into TOTAL
        box(970, 1025, 213, "MODULATION\nGENERATOR")
        arrow([(970, 213), (956, 213)], head: false); arrow([(1025, 213), (1036, 213)], head: false)
        arrow([(962, 213), (962, 182), (942, 182), (942, 175)]); dot(962, 213)
        // EG 1: OUT; into FREQ, and into the modulation VCA's CONTROL INPUT
        box(1150, 1205, 213, "ENVELOPE\nGENERATOR 1")
        arrow([(1150, 213), (1126, 213)], head: false)
        arrow([(1135, 213), (1135, 182), (1025, 182), (1025, 175)]); dot(1135, 213)
        arrow([(1135, 213), (1135, 268), (1144, 268)])
        // EG 2: REV OUT; into both CUTOFF FREQ inputs, and into the VCA beside INITIAL GAIN
        box(1240, 1295, 213, "ENVELOPE\nGENERATOR 2")
        arrow([(1295, 213), (1304, 213)], head: false)
        // (EG 2 rises between the low-pass's CUTOFF FREQ and INITIAL GAIN, and joins INITIAL GAIN's line into the VCA)
        arrow([(1262, 199), (1262, 182), (1153, 182), (1153, 175)]); arrow([(1225, 182), (1225, 175)]); dot(1225, 182)
        arrow([(1262, 182), (1262, 104), (1300, 104)], head: false); dot(1262, 182); dot(1300, 104)
        // the keyboard: KBD CV OUT and VCO 1+2 CV IN, TRIG OUT and TRIG IN
        box(1436, 1454, 240, "KBD", 13)
        arrow([(1445, 233), (1445, 213), (1439, 213)]); arrow([(1445, 213), (1461, 213)]); dot(1445, 213)
        arrow([(1445, 247), (1445, 268), (1433, 268)]); arrow([(1445, 268), (1456, 268)]); dot(1445, 268)
        // VCO 1+2 CV IN: to VCO 1, and on into VCO 2 CV IN; VCO 2 CV IN: to VCO 2
        arrow([(1408, 213), (1396, 213), (1396, 186), (1380, 186)]); dot(1396, 213)
        ctx.text("VCO 1", P(1377, 186), size: 7, weight: .semibold, anchor: .trailing)
        arrow([(1396, 213), (1396, 240), (1384, 240)])
        arrow([(1353, 240), (1344, 240), (1344, 253), (1334, 253)])
        ctx.text("VCO 2", P(1331, 253), size: 7, weight: .semibold, anchor: .trailing)
        // TRIG IN: EG 2, and on into EG 1 TRIG IN; EG 1 TRIG IN: EG 1
        arrow([(1402, 268), (1285, 268), (1285, 227)]); arrow([(1285, 268), (1261, 268)]); dot(1285, 268)
        arrow([(1230, 268), (1186, 268), (1186, 227)])

        // ---- sample & hold, the modulation VCA, the noise generator
        box(970, 1025, 322, "SAMPLE\n& HOLD")
        arrow([(953, 322), (970, 322)]); arrow([(1025, 322), (1033, 322)], head: false); arrow([(995, 284), (995, 309)])
        tri(1140, 322, "VCA")
        arrow([(1118, 322), (1129, 322)]); arrow([(1154, 322), (1172, 322)], head: false)
        arrow([(1160, 284), (1160, 297), (1144, 297), (1144, 312)])
        box(1265, 1320, 322, "NOISE\nGENERATOR")
        arrow([(1265, 322), (1254, 322)], head: false); arrow([(1320, 322), (1334, 322)], head: false)

        // ---- the external signal processor: amplifier -> band pass -> F-V; the amplifier also -> envelope follower -> TRIG
        ctx.line(P(905, 350), P(1548, 350), Palette.line, 1.0)
        ctx.text("EXTERNAL SIGNAL PROCESSOR", P(1060, 362), size: 9.5, weight: .semibold)
        tri(985, 393, "AMP")
        arrow([(952, 393), (973, 393)]); arrow([(999, 393), (1026, 393)], head: false)
        box(1070, 1125, 393, "BAND PASS\nFILTER")
        arrow([(1057, 393), (1070, 393)], head: false); arrow([(1125, 393), (1134, 393)], head: false)
        box(1180, 1230, 393, "F-V\nCONVERTER")
        arrow([(1165, 393), (1180, 393)], head: false); arrow([(1230, 393), (1241, 393)], head: false)
        box(1302, 1357, 393, "ENVELOPE\nFOLLOWER")
        arrow([(1010, 393), (1010, 416), (1288, 416), (1288, 398), (1302, 398)]); dot(1010, 393)
        arrow([(1357, 393), (1382, 393)], head: false); arrow([(1413, 393), (1437, 393)], head: false)
        ctx.text("PEAK", P(1338, 372) + CGPoint(x: -8, y: 0), size: 6.5, weight: .medium, color: Palette.inkDim, anchor: .trailing)
        // the power lamp's label
        ctx.text("ON", P(1345, 163) + CGPoint(x: 12, y: 0), size: 7, weight: .medium, color: Palette.inkDim, anchor: .leading)
    }

    static func strip(_ ctx: inout GraphicsContext) {
        let r = Geometry.strip
        ctx.fill(Path(CGRect(x: 0, y: r.minY + 4, width: r.width, height: r.height - 6)), with: .color(Color(white: 0.06)))
        ctx.text("FM-1 OUTPUTS, NOT ON AN MS-20 →", CGPoint(x: 1006, y: r.midY + 2), size: 8, weight: .semibold, color: Palette.inkDim, anchor: .trailing)
    }

    static func keyboard(_ ctx: inout GraphicsContext) {
        let r = Geometry.keys
        ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(Color(white: 0.07)))
        // the left cheek: the control wheel's slot and the momentary switch
        let w = Wheel.slot
        ctx.fill(Path(roundedRect: w, cornerRadius: 6), with: .color(.black))
        ctx.text("WHEEL", CGPoint(x: w.midX, y: w.minY - 9), size: 7.5, color: Palette.inkDim)
        ctx.circle(Wheel.button, 16, .color(Color(white: 0.02)))
        ctx.text("SWITCH", CGPoint(x: Wheel.button.x, y: Wheel.button.y + 27), size: 7.5, color: Palette.inkDim)
        for k in Keys.all where !k.black { ctx.fill(Path(roundedRect: k.rect, cornerRadius: 3), with: .linearGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.84)]), startPoint: CGPoint(x: 0, y: k.rect.minY), endPoint: CGPoint(x: 0, y: k.rect.maxY))) }
        for k in Keys.all where k.black { ctx.fill(Path(roundedRect: k.rect, cornerRadius: 2), with: .linearGradient(Gradient(colors: [Color(white: 0.16), Color(white: 0.03)]), startPoint: CGPoint(x: 0, y: k.rect.minY), endPoint: CGPoint(x: 0, y: k.rect.maxY))) }
    }
}

extension KnobKind {
    var isBipolar: Bool { if case .bipolar = self { return true } else { return false } }
}

func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }

/// what is where: the jacks, the cables' curves (shared by drawing and clicking)
public enum Hit {
    /// a cable's curve and its two ends; a cable to nothing hangs from its jack, its loose plug at the bottom (b nil)
    static func path(_ c: ShownCable, _ all: [ShownCable]) -> (Path, CGPoint, CGPoint?)? {
        guard let a = Layout.jack(c.cable.a)?.center else { return nil }
        guard let bj = c.cable.b else {
            let end = a + CGPoint(x: 9, y: 22)                  // (short, and its plug lies off sideways: clear of the jack below)
            var p = Path()
            p.move(to: a)
            p.addCurve(to: end, control1: a + CGPoint(x: 0, y: 12), control2: end + CGPoint(x: -6, y: -4))
            return (p, a, nil)
        }
        guard let b = Layout.jack(bj)?.center else { return nil }
        let d = hypot(b.x - a.x, b.y - a.y)
        let lowest = max(a.y, b.y)
        let sag = min(30 + 0.42 * d, max(20, (Geometry.strip.maxY + 30 - lowest) / 0.75))
        var p = Path()
        p.move(to: a)
        p.addCurve(to: b, control1: CGPoint(x: a.x + (b.x - a.x) * 0.08, y: a.y + sag), control2: CGPoint(x: b.x - (b.x - a.x) * 0.08, y: b.y + sag))
        return (p, a, b)
    }

    /// a point on a cable's curve that a click there would take as that cable (clear of every jack), for scripted clicks
    public static func pathPoint(_ c: ShownCable, _ all: [ShownCable]) -> (CGPoint, CGPoint, CGPoint?)? {
        guard let (p, a, b) = path(c, all) else { return nil }
        for t in stride(from: 0.5, to: 0.95, by: 0.05) {
            for u in [t, 1 - t] {
                if let q = p.trimmedPath(from: 0, to: u).currentPoint, target(at: q, cables: all) == .cable(c.id) { return (q, a, b) }
            }
        }
        return nil
    }

    /// the jack or cable at p (panel units): jacks first (a plug sits on its jack), then the cables, the top one first
    static func target(at p: CGPoint, cables: [ShownCable]) -> PanelTarget? {
        if let j = Layout.jacks.min(by: { hypot($0.center.x - p.x, $0.center.y - p.y) < hypot($1.center.x - p.x, $1.center.y - p.y) }),
           hypot(j.center.x - p.x, j.center.y - p.y) <= 17 {
            return .jack(j.id)
        }
        for c in cables.reversed() where c.alpha > 0.5 {
            if let (path, _, _) = path(c, cables), path.strokedPath(StrokeStyle(lineWidth: 14, lineCap: .round)).contains(p) {
                return .cable(c.id)
            }
        }
        return nil
    }
}

enum Wheel {
    static let slot = CGRect(x: 52, y: Geometry.keys.minY + 30, width: 36, height: 112)
    static let button = CGPoint(x: 125, y: Geometry.keys.minY + 64)
}

struct Key { let note: Int; let black: Bool; let rect: CGRect }

enum Keys {
    static let all: [Key] = {
        let x0 = Geometry.cheek, top = Geometry.keys.minY + 10, h = Geometry.keys.height - 20
        let whites = (Geometry.lowNote...Geometry.highNote).filter { ![1, 3, 6, 8, 10].contains($0 % 12) }
        let ww = (Geometry.size.width - x0 - 14) / CGFloat(whites.count)
        var keys: [Key] = []
        var i = 0
        for n in Geometry.lowNote...Geometry.highNote {
            if [1, 3, 6, 8, 10].contains(n % 12) {
                let x = x0 + CGFloat(i) * ww - ww * 0.3
                keys.append(Key(note: n, black: true, rect: CGRect(x: x, y: top, width: ww * 0.6, height: h * 0.62)))
            } else {
                keys.append(Key(note: n, black: false, rect: CGRect(x: x0 + CGFloat(i) * ww + 1, y: top, width: ww - 2, height: h)))
                i += 1
            }
        }
        return keys
    }()
}

// ---- the moving layer
enum Moving {
    static func draw(_ ctx: inout GraphicsContext, _ m: PanelFrame) {
        for k in Layout.knobs { pointer(&ctx, k, m.shown[k.param.rawValue]) }
        lamps(&ctx, m)
        keys(&ctx, m)
        for c in m.cables { cable(&ctx, c, m.cables, lit: m.hover == .cable(c.id)) }
        patching(&ctx, m)
        status(&ctx, m)
        if !m.connected {
            ctx.fill(Path(CGRect(origin: .zero, size: Geometry.size)), with: .color(.black.opacity(0.55)))
            let msg: String
            switch m.status {
            case .waiting: msg = "Waiting for the FM-1 …"
            case .lost(let s): msg = "Nothing from \(s) for a while: unplugged, or another firmware?"
            case .incompatible(let why): msg = why
            case .connected: msg = ""
            }
            ctx.text(msg, CGPoint(x: Geometry.size.width / 2, y: Geometry.panel.midY), size: 22, weight: .semibold, color: .white)
        }
    }

    static func pointer(_ ctx: inout GraphicsContext, _ k: KnobSpot, _ v: Double) {
        // a white line from the cap's middle out over the skirt to its edge
        let c = k.center, r = k.size.diameter / 2, a = Layout.angle(k.kind, value: v)
        var p = Path()
        p.move(to: polar(c, r * 0.10, a)); p.addLine(to: polar(c, r * 0.97, a))
        ctx.stroke(p, with: .color(Color(white: 0.92)), style: StrokeStyle(lineWidth: k.size == .standard ? 2.6 : 3.4, lineCap: .round))
    }

    static func lamps(_ ctx: inout GraphicsContext, _ m: PanelFrame) {
        for l in Layout.lamps {
            let on: Bool
            switch l.id {
            case .mg: on = m.live.lamps.contains(.mg)
            case .trigger: on = m.live.lamps.contains(.trigger)
            case .espPeak: on = m.live.lamps.contains(.espPeak)
            case .espTrigger: on = m.live.lamps.contains(.espTrigger)
            case .power: on = m.connected
            }
            guard on, m.connected else { continue }
            ctx.circle(l.center, 14, .radialGradient(Gradient(colors: [Palette.lampOn.opacity(0.55), .clear]), center: l.center, startRadius: 0, endRadius: 14))
            ctx.circle(l.center, 3.8, .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.75), Palette.lampOn]), center: l.center, startRadius: 0, endRadius: 4))
        }
    }

    static func keys(_ ctx: inout GraphicsContext, _ m: PanelFrame) {
        // the wheel: its ridges move with it, a mark at its centre position
        let w = Wheel.slot, off = CGFloat(m.live.wheel) / 127 * 40
        var inner = ctx
        inner.clip(to: Path(roundedRect: w.insetBy(dx: 3, dy: 3), cornerRadius: 4))
        inner.fill(Path(w.insetBy(dx: 5, dy: 3)), with: .linearGradient(Gradient(colors: [Color(white: 0.08), Color(white: 0.30), Color(white: 0.08)]), startPoint: CGPoint(x: 0, y: w.minY), endPoint: CGPoint(x: 0, y: w.maxY)))
        for i in -12...12 {
            let y = w.midY + CGFloat(i) * 8 - off.truncatingRemainder(dividingBy: 8)
            inner.line(CGPoint(x: w.minX + 6, y: y), CGPoint(x: w.maxX - 6, y: y), Color.black.opacity(0.6), 1.5)
        }
        inner.line(CGPoint(x: w.minX + 6, y: w.midY - off), CGPoint(x: w.maxX - 6, y: w.midY - off), Color(white: 0.9), 2.5)
        ctx.text(String(format: "%+.1f V", m.live.wheelVolts), CGPoint(x: w.midX, y: w.maxY + 11), size: 7.5, color: Palette.inkDim)
        // the momentary switch
        let b = Wheel.button
        ctx.circle(b, m.live.button ? 12 : 13, .radialGradient(Gradient(colors: [Color(white: m.live.button ? 0.25 : 0.45), Color(white: 0.12)]), center: CGPoint(x: b.x - 3, y: b.y - 4), startRadius: 0, endRadius: 14))
        // the key that counts
        guard let n = m.live.note, m.live.gate else { return }
        if let k = Keys.all.first(where: { $0.note == n }) {
            ctx.fill(Path(roundedRect: k.rect.insetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color(Palette.cables[0].opacity(k.black ? 0.85 : 0.65)))
        } else {
            // outside the MS-20's 37 keys: an arrow at that end, with the octaves
            let below = n < Geometry.lowNote, x = below ? Geometry.cheek - 14 : Geometry.size.width - 8
            let oct = below ? (Geometry.lowNote - n + 11) / 12 : (n - Geometry.highNote + 11) / 12
            ctx.text(below ? "◀︎ \(oct) oct" : "\(oct) oct ▶︎", CGPoint(x: x, y: Geometry.keys.maxY - 18), size: 10, weight: .bold,
                     color: Palette.cables[0], anchor: below ? .trailing : .trailing)
        }
    }

    static func cable(_ ctx: inout GraphicsContext, _ c: ShownCable, _ all: [ShownCable], lit: Bool = false) {
        guard let (p, a, b) = Hit.path(c, all) else { return }
        let color = Palette.cables[c.id % Palette.cables.count]
        rope(&ctx, p, a, b, color, alpha: c.alpha, lit: lit)
        if b == nil, let e = p.currentPoint {              // a cable to nothing: its loose plug, seen from the side
            var l = ctx
            l.opacity = c.alpha
            l.translateBy(x: e.x, y: e.y)
            l.rotate(by: .degrees(-58))
            l.fill(Path(roundedRect: CGRect(x: -5, y: -2, width: 10, height: 17), cornerRadius: 3), with: .color(Color(white: 0.08)))
            l.fill(Path(CGRect(x: -5, y: 3, width: 10, height: 2.5)), with: .color(color))
            l.fill(Path(roundedRect: CGRect(x: -1.8, y: 15, width: 3.6, height: 9), cornerRadius: 1.5), with: .color(Color(white: 0.78)))
        }
    }

    static func rope(_ ctx: inout GraphicsContext, _ p: Path, _ a: CGPoint, _ b: CGPoint?, _ color: Color, alpha: Double, lit: Bool) {
        var layer = ctx
        layer.opacity = alpha
        layer.drawLayer { l in
            if lit { l.stroke(p, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 14, lineCap: .round)) }
            l.stroke(p.offsetBy(dx: 3, dy: 6), with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            l.stroke(p, with: .color(color.mix(with: .black, by: 0.35)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            l.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 6.5, lineCap: .round))
            l.stroke(p.offsetBy(dx: -1, dy: -1.6), with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            plug(&l, a, color)
            if let b { plug(&l, b, color) }
        }
    }

    /// patching: a ring round the jack under the pointer, the loose cable from the jack clicked first, a notice
    static func patching(_ ctx: inout GraphicsContext, _ m: PanelFrame) {
        if case .jack(let j) = m.hover, let c = Layout.jack(j)?.center {
            ctx.ring(c, 18, Color(red: 1, green: 0.85, blue: 0.3).opacity(0.9), 2.2)
        }
        if let j = m.pending, let a = Layout.jack(j)?.center {
            let slot = m.state?.cables.firstIndex(where: { $0 == nil }) ?? 0
            let color = Palette.cables[slot % Palette.cables.count]
            ctx.ring(a, 19, color, 2.5)
            if let q = m.pointer {
                let d = hypot(q.x - a.x, q.y - a.y), sag = min(20 + 0.30 * d, 160)
                var p = Path()
                p.move(to: a)
                p.addCurve(to: q, control1: CGPoint(x: a.x + (q.x - a.x) * 0.08, y: a.y + sag), control2: CGPoint(x: q.x - (q.x - a.x) * 0.08, y: q.y + sag * 0.6))
                rope(&ctx, p, a, q, color, alpha: 0.85, lit: false)
            }
        }
        if let n = m.notice {
            let r = CGRect(x: Geometry.size.width / 2 - 330, y: Geometry.strip.minY + 10, width: 660, height: 40)
            ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(Color(red: 0.45, green: 0.12, blue: 0.08).opacity(0.95)))
            ctx.text(n, CGPoint(x: r.midX, y: r.midY), size: 13, weight: .semibold, color: .white)
        }
    }

    static func plug(_ ctx: inout GraphicsContext, _ c: CGPoint, _ color: Color) {
        ctx.circle(c + CGPoint(x: 2, y: 4), 13.5, .color(.black.opacity(0.4)))
        ctx.circle(c, 13, .radialGradient(Gradient(colors: [Color(white: 0.28), Color(white: 0.04)]), center: CGPoint(x: c.x - 4, y: c.y - 5), startRadius: 0, endRadius: 15))
        ctx.ring(c, 9.5, color, 2.4)
        ctx.circle(c, 4, .color(Color(white: 0.02)))
    }

    static func status(_ ctx: inout GraphicsContext, _ m: PanelFrame) {
        let y = Geometry.strip.midY + 2
        guard let s = m.state else { return }
        var t = String(format: "%02d  %@", s.preset + 1, s.name)
        if s.edited { t += " *" }
        ctx.text(t, CGPoint(x: 26, y: y), size: 15, weight: .bold, color: Color(white: 0.92), anchor: .leading)
        var right = String(format: "OCT %+d", s.octave)
        if s.hold { right += "   HOLD" }
        ctx.text(right, CGPoint(x: 330, y: y), size: 12, weight: .semibold, color: Palette.inkDim, anchor: .leading)
        if case .connected(let src) = m.status {
            ctx.text(src, CGPoint(x: Geometry.size.width - 20, y: y), size: 10, weight: .regular, color: Palette.inkDim, anchor: .trailing)
        }
    }
}
