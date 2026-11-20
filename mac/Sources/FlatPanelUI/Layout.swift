// SPDX-License-Identifier: GPL-3.0-only
// Where everything is on the panel, in the panel's own units (its top-left corner at 0, 0). Measured on photographs:
// the knob section (VCO 1 to EG 2) on a frontal photograph of an original MS-20's (V(): its pixels, with the camera's
// keystone undone), the patch panel on one of an MS-20 mini's, whose layout is the same (P()). The drawing itself is
// this program's own; the instrument's makers' names and logo are not on it.
import CoreGraphics
import FlatLink

/// a pixel of the patch panel's photograph -> panel units
@inline(__always) func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x - 5, y: (y - 40) * 1.07) }
/// The knob section is a grid: each column's x and each row's y, in panel units. Measured on the original's photograph
/// (1600 px wide; its vertical lines lean in toward its bottom by about 7 %, undone first: x' = 820 + (x - 820) / (1 - 0.00007 y),
/// then units = 0.556 (x' - 3), 8 + 0.594 y), then snapped so that what is in line on the instrument is in line here.
enum Col { static let vco1: CGFloat = 68.5, vco2: CGFloat = 190, mix: CGFloat = 302.5, hpf: CGFloat = 410.6, lpf: CGFloat = 519
           static let mg: CGFloat = 624.5, eg1: CGFloat = 731.7, eg2: CGFloat = 840, porta: CGFloat = 72 }
enum Row { static let top: CGFloat = 107.5, selector: CGFloat = 111, second: CGFloat = 220, eg2Atk: CGFloat = 210, peak: CGFloat = 232.5
           static let eg1Top: CGFloat = 294, scale: CGFloat = 333, mod1: CGFloat = 376, mod2: CGFloat = 455 }
@inline(__always) func U(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

public enum Geometry {
    /// the MS-20's front panel
    public static let panel = CGRect(x: 0, y: 0, width: 1545, height: 514)
    /// below it: what the FM-1 has and an MS-20 has not
    public static let strip = CGRect(x: 0, y: 514, width: 1545, height: 62)
    /// the keyboard and the left cheek with the wheel and the momentary switch
    public static let keys = CGRect(x: 0, y: 576, width: 1545, height: 224)
    public static let size = CGSize(width: 1545, height: 800)
    public static let cheek: CGFloat = 170
    /// the MS-20's keyboard: 37 keys, C to C (the lowest C is MIDI note 48 in FLAT-20)
    public static let lowNote = 48, highNote = 84
}

public enum KnobSize: Sendable {
    /// the filters' CUTOFF FREQUENCY and VOLUME
    case big
    /// the VCOs' four-way switches
    case selector
    case standard
    /// the skirt's diameter (the cap on it is about 0.7 of that)
    var diameter: CGFloat { switch self { case .big: 60; case .selector: 68; case .standard: 42 } }
    /// how far below the centre the knob's name is printed
    var labelDrop: CGFloat { switch self { case .big: 51; case .selector: 45; case .standard: 35.5 } }
}

public enum KnobKind: Sendable {
    /// 0 ... 10
    case dial
    /// -5 ... 0 ... +5
    case bipolar
    /// a four-way switch, with what is printed at each position, at that distance from the centre
    case rotary([SwitchMark], CGFloat)
    /// VCO 1's PW: ticks, and a pulse at each end and the middle (1:1, narrow, nothing)
    case pw
    /// the MG's WAVE FORM: ticks, and the wave's shape at each end and the middle
    case mgWave
}

public enum SwitchMark: Equatable, Sendable {
    case text(String)
    case triangle, sawtooth, square, pulse, noise, ring
    /// VCO 1's variable pulse: a pulse, an arrow both ways, a narrower pulse
    case pwPulse
    /// the MG's rising ramp, and its narrow rectangle
    case ramp, narrow
}

public struct KnobSpot: Sendable {
    public let param: Param
    public let center: CGPoint
    public let size: KnobSize
    public let kind: KnobKind
    public let label: String
}

public struct JackSpot: Sendable {
    public let id: JackID
    public let center: CGPoint
    public let label: String
    /// the voltage range printed under the jack, if any
    public let legend: String?
    /// true: a jack an MS-20 does not have (drawn in the strip below the panel)
    public let extra: Bool
    /// where its name is printed (above, unless the diagram's arrows need the room)
    public var place: LabelPlace = .above
    /// where the legend goes, if not under the jack (an offset from the centre; left of it right-aligned, right of it left-aligned)
    public var legendAt: CGPoint? = nil
}

public enum LabelPlace: Sendable { case above, below, right, at(CGFloat, CGFloat) }

public enum LampID: Sendable { case mg, trigger, espPeak, espTrigger, power }

public struct LampSpot: Sendable {
    public let id: LampID
    public let center: CGPoint
}

public enum Layout {
    /// a four-way switch's positions, 30° apart (measured on the original)
    static let switchAngles: [Double] = [-45, -15, 15, 45]

    public static let knobs: [KnobSpot] = [
        // VCO 1, VCO 2
        .init(param: .v1wave, center: U(Col.vco1, Row.selector), size: .selector, kind: .rotary([.triangle, .sawtooth, .pwPulse, .noise], 52), label: "WAVE FORM"),
        .init(param: .v1pw, center: U(Col.vco1, Row.second), size: .standard, kind: .pw, label: "PW"),
        .init(param: .v1scale, center: U(Col.vco1, Row.scale), size: .selector, kind: .rotary([.text("32′"), .text("16′"), .text("8′"), .text("4′")], 48), label: "SCALE"),
        .init(param: .v2wave, center: U(Col.vco2, Row.selector), size: .selector, kind: .rotary([.sawtooth, .square, .pulse, .ring], 52), label: "WAVE FORM"),
        .init(param: .v2pitch, center: U(Col.vco2, Row.second), size: .standard, kind: .bipolar, label: "PITCH"),
        .init(param: .v2scale, center: U(Col.vco2, Row.scale), size: .selector, kind: .rotary([.text("16′"), .text("8′"), .text("4′"), .text("2′")], 48), label: "SCALE"),
        .init(param: .porta, center: U(Col.porta, Row.mod2), size: .standard, kind: .dial, label: "TIME"),
        .init(param: .tune, center: U(Col.vco2, Row.mod2), size: .standard, kind: .bipolar, label: ""),
        // mixer, filters
        .init(param: .mix1, center: U(Col.mix, Row.top), size: .standard, kind: .dial, label: "VCO 1 LEVEL"),
        .init(param: .mix2, center: U(Col.mix, Row.peak), size: .standard, kind: .dial, label: "VCO 2 LEVEL"),
        .init(param: .hpCut, center: U(Col.hpf, Row.top), size: .big, kind: .dial, label: "CUTOFF FREQUENCY"),
        .init(param: .hpPeak, center: U(Col.hpf, Row.peak), size: .standard, kind: .dial, label: "PEAK"),
        .init(param: .lpCut, center: U(Col.lpf, Row.top), size: .big, kind: .dial, label: "CUTOFF FREQUENCY"),
        .init(param: .lpPeak, center: U(Col.lpf, Row.peak), size: .standard, kind: .dial, label: "PEAK"),
        // the modulation knobs
        .init(param: .fmMg, center: U(Col.mix, Row.mod1), size: .standard, kind: .dial, label: "MG/T.EXT"),
        .init(param: .fmEg, center: U(Col.mix, Row.mod2), size: .standard, kind: .dial, label: "EG1/EXT"),
        .init(param: .hpMg, center: U(Col.hpf, Row.mod1), size: .standard, kind: .dial, label: "MG/T.EXT"),
        .init(param: .hpEg, center: U(Col.hpf, Row.mod2), size: .standard, kind: .dial, label: "EG2/EXT"),
        .init(param: .lpMg, center: U(Col.lpf, Row.mod1), size: .standard, kind: .dial, label: "MG/T.EXT"),
        .init(param: .lpEg, center: U(Col.lpf, Row.mod2), size: .standard, kind: .dial, label: "EG2/EXT"),
        // MG, EG 1, EG 2
        .init(param: .mgWave, center: U(Col.mg, Row.mod1), size: .standard, kind: .mgWave, label: "WAVE FORM"),
        .init(param: .mgRate, center: U(Col.mg, Row.mod2), size: .standard, kind: .dial, label: "FREQUENCY"),
        .init(param: .e1Delay, center: U(Col.eg1, Row.eg1Top), size: .standard, kind: .dial, label: "DELAY TIME"),
        .init(param: .e1Atk, center: U(Col.eg1, Row.mod1), size: .standard, kind: .dial, label: "ATTACK TIME"),
        .init(param: .e1Rel, center: U(Col.eg1, Row.mod2), size: .standard, kind: .dial, label: "RELEASE TIME"),
        .init(param: .e2Hold, center: U(Col.eg2, Row.top), size: .standard, kind: .dial, label: "HOLD TIME"),
        .init(param: .e2Atk, center: U(Col.eg2, Row.eg2Atk), size: .standard, kind: .dial, label: "ATTACK TIME"),
        .init(param: .e2Dec, center: U(Col.eg2, Row.eg1Top), size: .standard, kind: .dial, label: "DECAY TIME"),
        .init(param: .e2Sus, center: U(Col.eg2, Row.mod1), size: .standard, kind: .dial, label: "SUSTAIN LEVEL"),
        .init(param: .e2Rel, center: U(Col.eg2, Row.mod2), size: .standard, kind: .dial, label: "RELEASE TIME"),
        // the patch panel's knobs
        .init(param: .volume, center: P(1400, 115), size: .big, kind: .dial, label: "VOLUME"),
        .init(param: .espLevel, center: P(948, 465), size: .standard, kind: .dial, label: "SIGNAL LEVEL"),
        .init(param: .espLow, center: P(1027, 465), size: .standard, kind: .dial, label: "LOW CUT FREQ"),
        .init(param: .espHigh, center: P(1108, 465), size: .standard, kind: .dial, label: "HIGH CUT FREQ"),
        .init(param: .espCv, center: P(1188, 465), size: .standard, kind: .dial, label: "CV ADJUST"),
        .init(param: .espThr, center: P(1268, 465), size: .standard, kind: .dial, label: "THRESHOLD LEVEL"),
    ]

    public static let jacks: [JackSpot] = [
        // row 1: the inputs to the voice
        .init(id: .input(.total), center: P(942, 143), label: "TOTAL", legend: "-5V~+5V", extra: false),
        .init(id: .input(.freq), center: P(1025, 143), label: "FREQ", legend: "-5V~+5V", extra: false),
        .init(id: .input(.extIn), center: P(1090, 143), label: "EXT SIGNAL IN", legend: "3VPP MAX", extra: false),
        .init(id: .input(.hpCut), center: P(1153, 143), label: "CUTOFF FREQ", legend: "-5V~+5V", extra: false),
        .init(id: .input(.lpCut), center: P(1225, 143), label: "CUTOFF FREQ", legend: "-5V~+5V", extra: false),
        .init(id: .input(.gain), center: P(1300, 143), label: "INITIAL GAIN", legend: "0V~+5V", extra: false),
        .init(id: .output(.signal), center: P(1502, 88), label: "SIGNAL OUT", legend: nil, extra: false),
        .init(id: .output(.phones), center: P(1502, 160), label: "PHONES", legend: nil, extra: false),
        // row 2
        .init(id: .output(.mgTri), center: P(940, 213), label: "OUT", legend: "±2.5V", extra: false),
        .init(id: .output(.mgRect), center: P(1052, 213), label: "OUT", legend: "0/+5V", extra: false),
        .init(id: .output(.eg1), center: P(1110, 213), label: "OUT", legend: "0→+5V", extra: false, legendAt: CGPoint(x: -13, y: -24)),
        .init(id: .output(.eg2Rev), center: P(1320, 213), label: "REV OUT", legend: "0→-5V", extra: false),
        .init(id: .input(.vco2Cv), center: P(1368, 240), label: "VCO 2\nCV IN", legend: nil, extra: false, place: .at(0, -28)),
        .init(id: .input(.vcoCv), center: P(1423, 213), label: "VCO 1+2 CV IN", legend: nil, extra: false),
        .init(id: .output(.kbdCv), center: P(1477, 213), label: "KBD CV OUT", legend: nil, extra: false),
        // row 3
        .init(id: .input(.shClock), center: P(995, 268), label: "CLOCK", legend: "GND", extra: false),
        .init(id: .output(.eg1Rev), center: P(1105, 268), label: "REV OUT", legend: "+5V→0", extra: false, legendAt: CGPoint(x: -18, y: 12)),
        .init(id: .input(.mvcaCtl), center: P(1160, 268), label: "CONTROL\nINPUT", legend: nil, extra: false, place: .at(0, -28)),
        .init(id: .input(.eg1Trig), center: P(1245, 268), label: "EG 1\nTRIG IN", legend: "GND", extra: false, place: .at(0, -28)),
        .init(id: .input(.trig), center: P(1417, 268), label: "TRIG IN", legend: "GND", extra: false),
        .init(id: .output(.kbdTrig), center: P(1472, 268), label: "TRIG OUT", legend: "GND", extra: false),
        // row 4
        .init(id: .input(.shIn), center: P(938, 322), label: "IN", legend: nil, extra: false),
        .init(id: .output(.sh), center: P(1048, 322), label: "OUT", legend: nil, extra: false),
        .init(id: .input(.mvcaIn), center: P(1103, 322), label: "IN", legend: nil, extra: false),
        .init(id: .output(.mvca), center: P(1187, 322), label: "OUT", legend: nil, extra: false),
        .init(id: .output(.pink), center: P(1238, 322), label: "PINK", legend: nil, extra: false),
        .init(id: .output(.white), center: P(1350, 322), label: "WHITE", legend: nil, extra: false),
        .init(id: .output(.wheel), center: P(1408, 322), label: "WHEEL", legend: "-5V~+5V", extra: false),
        .init(id: .output(.button), center: P(1463, 322), label: "SWITCH", legend: "GND", extra: false),
        // the external signal processor
        .init(id: .input(.espIn), center: P(937, 393), label: "SIGNAL IN", legend: nil, extra: false),
        .init(id: .output(.espAmp), center: P(1042, 393), label: "OUT", legend: nil, extra: false),
        .init(id: .output(.espBpf), center: P(1150, 393), label: "OUT", legend: nil, extra: false),
        .init(id: .output(.espFv), center: P(1257, 393), label: "F-V CV OUT", legend: nil, extra: false),
        .init(id: .output(.espEnv), center: P(1398, 393), label: "ENV OUT", legend: nil, extra: false),
        .init(id: .output(.espTrig), center: P(1453, 393), label: "TRIG OUT", legend: "GND", extra: false),
        // the FM-1's: not on an MS-20's panel
        .init(id: .output(.vco1), center: CGPoint(x: 1040, y: 545), label: "VCO 1", legend: nil, extra: true),
        .init(id: .output(.vco2), center: CGPoint(x: 1110, y: 545), label: "VCO 2", legend: nil, extra: true),
    ]

    public static let lamps: [LampSpot] = [
        .init(id: .mg, center: U(Col.mg, 294)),
        .init(id: .trigger, center: U(792, 238)),
        .init(id: .espPeak, center: P(1338, 372)),
        .init(id: .espTrigger, center: P(1482, 371)),
        .init(id: .power, center: P(1345, 163)),
    ]

    /// the trimmers' access holes beside the VCO knobs and under the filters' cutoffs (the original's)
    public static let holes: [CGPoint] = [U(116, 260), U(234, 260), U(116, 374), U(234, 374), U(118, 483), U(235, 483), U(372, 181), U(481, 181)]

    public static func jack(_ id: JackID) -> JackSpot? { jacks.first { $0.id == id } }

    /// the angle of a knob's pointer, in degrees from straight up (clockwise positive)
    public static func angle(_ kind: KnobKind, value: Double) -> Double {
        switch kind {
        case .dial, .bipolar, .pw, .mgWave: return -150 + 300 * min(1, max(0, value))
        case .rotary:
            // value as a continuous position 0 ... 3 (animated between detents)
            let p = min(3, max(0, value * 3))
            let i = min(2, Int(p)), f = p - Double(i)
            return switchAngles[i] + (switchAngles[i + 1] - switchAngles[i]) * f
        }
    }
}
