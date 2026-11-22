// SPDX-License-Identifier: GPL-3.0-only
// Decoder/encoder for the FLAT-20 SysEx panel link protocol (firmware/src/ms20_link.h). Pure Swift, no UI or CoreMIDI.

/// A jack on the patch panel.
public enum JackID: Hashable, Sendable {
    case output(Source)
    case input(Destination)

    /// Firmware jack index (MS_JACK_* in ms20.h): outputs starting at 1, followed by inputs.
    public var number: Int {
        switch self {
        case .output(let s): return s.rawValue
        case .input(let d): return Source.allCases.count - 1 + d.rawValue
        }
    }
    public init?(number n: Int) {
        let ns = Source.allCases.count
        if n > 0, n < ns, let s = Source(rawValue: n) { self = .output(s) }
        else if n >= ns, let d = Destination(rawValue: n - ns + 1), d != .none { self = .input(d) }
        else { return nil }
    }
}

/// A patch cable connecting two jacks (or a dummy plug when `b` is nil).
public struct Cable: Equatable, Hashable, Sendable {
    public var a: JackID
    public var b: JackID?
    public init(_ a: JackID, _ b: JackID?) { self.a = a; self.b = b }
    /// Standard output-to-input cable.
    public init(source: Source, destination: Destination) { self.init(.output(source), .input(destination)) }
    public func touches(_ j: JackID) -> Bool { a == j || b == j }
    public var ends: [JackID] { [a] + (b.map { [$0] } ?? []) }
    /// Cables are undirected: (a, b) equals (b, a).
    public static func == (l: Cable, r: Cable) -> Bool { (l.a == r.a && l.b == r.b) || (l.b != nil && l.a == r.b && l.b == r.a) }
    public func hash(into h: inout Hasher) { h.combine(Set(ends)) }
}

/// Full FM-1 patch state (decoded from a STATE SysEx message).
public struct PatchState: Equatable, Sendable {
    /// 0...127 per Param, in Param enum order.
    public var values: [UInt8]
    /// up to LinkFormat.cables slots; nil = the slot is empty
    public var cables: [Cable?]
    public var preset: Int
    public var name: String
    public var hold: Bool
    public var edited: Bool
    public var octave: Int
    /// the firmware takes CABLES from the computer (older firmware: a panel only shows)
    public var takesCables: Bool

    public init(values: [UInt8], cables: [Cable?], preset: Int, name: String, hold: Bool, edited: Bool, octave: Int, takesCables: Bool = false) {
        self.values = values; self.cables = cables; self.preset = preset; self.name = name
        self.hold = hold; self.edited = edited; self.octave = octave; self.takesCables = takesCables
    }

    public subscript(_ p: Param) -> UInt8 { values[p.rawValue] }
    /// a knob as its scale reads: 0...10
    public func dial(_ p: Param) -> Double { Double(values[p.rawValue]) / 127.0 * 10.0 }
    /// a four-way switch's position: 0...3
    public func position(_ p: Param) -> Int { Int(values[p.rawValue] >> 5) & 3 }
}

/// what is happening now (a LIVE message)
public struct LiveState: Equatable, Sendable {
    public var gate: Bool
    /// the key that counts (MIDI note); nil = none yet
    public var note: Int?
    /// -127...127 = -5...+5 V
    public var wheel: Int
    public var button: Bool
    public var lamps: Lamps

    public init(gate: Bool = false, note: Int? = nil, wheel: Int = 0, button: Bool = false, lamps: Lamps = []) {
        self.gate = gate; self.note = note; self.wheel = wheel; self.button = button; self.lamps = lamps
    }
    public var wheelVolts: Double { Double(wheel) * 5.0 / 127.0 }
}

public struct Lamps: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let mg = Lamps(rawValue: 1)
    public static let trigger = Lamps(rawValue: 2)
    public static let espTrigger = Lamps(rawValue: 4)
    public static let espPeak = Lamps(rawValue: 8)
}

public enum LinkMessage: Equatable, Sendable {
    case state(PatchState)
    case live(LiveState)
}

public enum LinkError: Error, Equatable, Sendable {
    /// not this link's message at all (another device's SysEx): ignore quietly
    case notOurs
    /// ours, but from firmware built with a different message format or different lists of knobs and jacks
    case incompatible(String)
    case malformed(String)
}

public enum LinkDecoder {
    static let head: [UInt8] = [0xF0, LinkFormat.id, 0x46, 0x32, 0x30]

    /// one complete SysEx message, F0 through F7
    public static func decode(_ m: [UInt8]) throws(LinkError) -> LinkMessage {
        guard m.count >= 8, Array(m.prefix(5)) == head, m.last == 0xF7 else { throw .notOurs }
        guard m[5] == LinkFormat.version else {
            throw .incompatible("the FM-1 sends format \(m[5]); this app reads format \(LinkFormat.version)")
        }
        let body = m[7..<(m.count - 1)]
        if body.contains(where: { $0 >= 0x80 }) { throw .malformed("a byte with bit 7 inside the message") }
        let b = Array(body)
        switch m[6] {
        case LinkFormat.state: return .state(try state(b))
        case LinkFormat.live: return .live(try live(b))
        default: throw .malformed("unknown message type \(m[6])")
        }
    }

    static func state(_ b: [UInt8]) throws(LinkError) -> PatchState {
        let np = Param.allCases.count, ns = Source.allCases.count, nd = Destination.allCases.count, nc = LinkFormat.cables
        guard b.count >= 3 else { throw .malformed("STATE too short") }
        guard Int(b[0]) == np, Int(b[1]) == ns, Int(b[2]) == nd else {
            throw .incompatible("the FM-1 has \(b[0]) knobs, \(b[1]) outputs, \(b[2]) inputs; this app knows \(np), \(ns), \(nd)")
        }
        guard b.count == 3 + np + 2 * nc + 3 + 12 else { throw .malformed("STATE is \(b.count) bytes, not \(3 + np + 2 * nc + 15)") }
        var i = 3
        let values = Array(b[i..<(i + np)]); i += np
        var cables: [Cable?] = []
        for _ in 0..<nc {
            let x = JackID(number: Int(b[i])), y = JackID(number: Int(b[i + 1])); i += 2
            if let x { cables.append(Cable(x, y)) } else if let y { cables.append(Cable(y, nil)) } else { cables.append(nil) }
        }
        let preset = Int(b[i]), flags = b[i + 1], octave = Int(b[i + 2]) - 3; i += 3
        let name = String(decoding: b[i..<(i + 12)].prefix { $0 != 0 }, as: UTF8.self)
        return PatchState(values: values, cables: cables, preset: preset, name: name,
                          hold: flags & 1 != 0, edited: flags & 2 != 0, octave: octave, takesCables: flags & LinkFormat.takesCables != 0)
    }

    static func live(_ b: [UInt8]) throws(LinkError) -> LiveState {
        guard b.count == 6 else { throw .malformed("LIVE is \(b.count) bytes, not 6") }
        let gate = b[0] != 0, note = Int(b[1])
        let wheel = (Int(b[2]) << 7 | Int(b[3])) - 127
        return LiveState(gate: gate, note: (note == 127 && !gate) ? nil : note, wheel: max(-127, min(127, wheel)),
                         button: b[4] != 0, lamps: Lamps(rawValue: b[5] & 0x0F))
    }
}

public enum LinkEncoder {
    /// the CABLES message (computer -> FM-1): the whole patch panel, slot by slot (nil: empty)
    public static func cables(_ c: [Cable?]) -> [UInt8] {
        var m: [UInt8] = LinkDecoder.head + [LinkFormat.version, LinkFormat.cableSet, UInt8(Source.allCases.count), UInt8(Destination.allCases.count)]
        for i in 0..<LinkFormat.cables {
            let x = i < c.count ? c[i] : nil
            m += [UInt8(x?.a.number ?? 0), UInt8(x?.b?.number ?? 0)]
        }
        return m + [0xF7]
    }
}

/// SysEx messages out of a MIDI byte stream: realtime bytes may sit inside a message, any other status byte ends an
/// unfinished one, and a message that grows past `limit` is dropped (not ours: ours are under 100 bytes).
public struct SysExAssembler: Sendable {
    var buf: [UInt8] = []
    var on = false
    let limit: Int
    public init(limit: Int = 512) { self.limit = limit }

    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [[UInt8]] {
        var out: [[UInt8]] = []
        for b in bytes {
            if b >= 0xF8 { continue }
            if b == 0xF0 { buf = [0xF0]; on = true; continue }
            guard on else { continue }
            if b == 0xF7 {
                buf.append(b); out.append(buf); buf = []; on = false
            } else if b & 0x80 != 0 {
                buf = []; on = false
            } else if buf.count < limit {
                buf.append(b)
            } else {
                buf = []; on = false
            }
        }
        return out
    }
}
