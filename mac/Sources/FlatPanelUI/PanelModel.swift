// SPDX-License-Identifier: GPL-3.0-only
// Observable panel state backed by incoming FM-1 STATE/LIVE packets, with ~80 ms knob interpolation
// and cable fade transitions.
import Foundation
import Observation
import FlatLink

public enum LinkStatus: Equatable, Sendable {
    /// No packets received yet.
    case waiting
    /// Packet received within the last 2.5 s (FM-1 sends at >= 1 Hz).
    case connected(source: String)
    /// Previously connected, now timed out.
    case lost(source: String)
    /// Firmware link version or parameter/jack count mismatch.
    case incompatible(String)
}

public struct ShownCable: Identifiable, Equatable, Sendable {
    /// Cable slot index (0..<8); each slot has a fixed color.
    public let id: Int
    public let cable: Cable
    public var alpha: Double
}

/// Snapshot passed to the renderer (value type so drawing can run off the main actor).
public struct PanelFrame: Sendable {
    public var state: PatchState?
    public var live: LiveState
    public var status: LinkStatus
    public var shown: [Double]
    public var cables: [ShownCable]
    /// Interactive patching state: first clicked jack, pointer position, hovered target, status notice.
    public var pending: JackID? = nil
    public var pointer: CGPoint? = nil
    public var hover: PanelTarget? = nil
    public var notice: String? = nil
    public var canPatch = false
    public var connected: Bool { if case .connected = status { return true } else { return false } }
}

/// what is under the pointer
public enum PanelTarget: Equatable, Sendable {
    case jack(JackID)
    /// a cable, by its slot
    case cable(Int)
}

@MainActor @Observable
public final class PanelModel {
    public var frame: PanelFrame {
        PanelFrame(state: state, live: live, status: status, shown: shown, cables: cables, pending: pending, pointer: pointer,
                   hover: canPatch ? hover : nil, notice: notice, canPatch: canPatch)
    }

    public private(set) var state: PatchState?
    public private(set) var live = LiveState()
    public private(set) var status: LinkStatus = .waiting
    /// every knob as the panel shows it now: 0 ... 1 (a switch: position / 3)
    public private(set) var shown: [Double] = Array(repeating: 0, count: Param.allCases.count)
    public private(set) var cables: [ShownCable] = []
    var lastHeard: Date?
    var source = ""
    var animating = false
    /// patching
    public private(set) var pending: JackID?
    public private(set) var pointer: CGPoint?
    public private(set) var hover: PanelTarget?
    public private(set) var notice: String?
    var noticeUntil = Date.distantPast
    /// sends a SysEx to the FM-1; false if there is nowhere to send it (set by the app; nil: the panel only shows)
    public var send: (@MainActor ([UInt8]) -> Bool)?
    /// patching is possible: the FM-1 is heard, its firmware takes cables, and there is a way to reach it
    public var canPatch: Bool { connected && state?.takesCables == true && send != nil }
    /// false: no easing (a still picture, panel-render)
    public var animates = true

    public init() {}

    /// a message from the FM-1 (any SysEx: what is not ours is ignored)
    public func receive(_ message: [UInt8], from source: String, at now: Date = Date()) {
        let m: LinkMessage
        do { m = try LinkDecoder.decode(message) } catch {
            if case .incompatible(let why) = error { status = .incompatible(why); lastHeard = now }
            return
        }
        lastHeard = now
        self.source = source
        status = .connected(source: source)
        switch m {
        case .state(let s): apply(s)
        case .live(let l): live = l
        }
    }

    // ---- patching with the mouse (PatchEditor's rules)

    /// the pointer moved over the panel (panel units), or left it (nil)
    public func pointerMoved(_ p: CGPoint?) {
        pointer = p
        hover = p.flatMap { Hit.target(at: $0, cables: cables) }
    }

    /// a click on the panel (panel units); option: the Option key was down (a dummy plug)
    public func click(at p: CGPoint, option: Bool = false) {
        guard let s = state else { return }
        guard canPatch else {
            if connected && !s.takesCables { say("This FM-1's firmware does not take cables from the Mac: update it to patch from here") }
            return
        }
        var e = PatchEditor(cables: s.cables, pending: pending)
        let outcome: PatchEditor.Outcome
        switch Hit.target(at: p, cables: cables) {
        case .jack(let j): outcome = option ? e.dummy(j) : e.click(j)
        case .cable(let i): outcome = e.clickCable(i)
        case nil:
            pending = nil                                   // a click on the panel itself puts the loose plug down
            return
        }
        pending = e.pending
        switch outcome {
        case .unchanged: break
        case .refused(let why): say(why)
        case .changed:
            guard send?(LinkEncoder.cables(e.cables)) == true else { say("Could not reach the FM-1"); return }
            var next = s                                    // shown at once; the FM-1's STATE confirms it a moment later
            next.cables = e.cables
            next.edited = true
            apply(next)
        }
    }

    /// Esc: the loose plug is put down
    public func cancelPatching() { pending = nil }

    func say(_ s: String, for seconds: Double = 3) {
        notice = s
        noticeUntil = Date().addingTimeInterval(seconds)
    }

    /// called every half second or so: notices silence
    public func tick(now: Date = Date()) {
        if notice != nil && now > noticeUntil { notice = nil }
        guard let t = lastHeard, case .connected(let src) = status else { return }
        if now.timeIntervalSince(t) > 2.5 { status = .lost(source: src) }
    }

    public var connected: Bool { if case .connected = status { return true } else { return false } }

    func target(_ s: PatchState) -> [Double] {
        Param.allCases.map { p in
            if case .rotary = Layout.kind(p) { return Double(s.position(p)) / 3 }
            return Double(s[p]) / 127
        }
    }

    func apply(_ s: PatchState) {
        let first = state == nil
        state = s
        var next: [ShownCable] = []
        for (i, c) in s.cables.enumerated() {
            guard let c else { continue }
            if let old = cables.first(where: { $0.id == i && $0.cable == c }) { next.append(old) }
            else { next.append(ShownCable(id: i, cable: c, alpha: first || !animates ? 1 : 0)) }
        }
        // a cable pulled out (or moved: the old one goes, the new one comes) fades away
        for old in cables where !next.contains(where: { $0.id == old.id && $0.cable == old.cable }) {
            next.append(ShownCable(id: old.id, cable: old.cable, alpha: animates ? old.alpha : 0))
        }
        cables = next.filter { $0.alpha > 0 || s.cables.indices.contains($0.id) && s.cables[$0.id] == $0.cable }
        if first || !animates { shown = target(s) }
        startAnimating()
    }

    func startAnimating() {
        guard animates, !animating else { return }
        animating = true
        Task { @MainActor in
            var last = Date()
            while animating {
                try? await Task.sleep(for: .milliseconds(16))
                let now = Date(), dt = min(0.1, now.timeIntervalSince(last)); last = now
                animating = step(dt)
            }
        }
    }

    /// one frame of easing; false when everything is where it should be
    func step(_ dt: Double) -> Bool {
        guard let s = state else { return false }
        let want = target(s), k = 1 - exp(-dt / 0.045)
        var moving = false
        var v = shown
        for i in v.indices {
            let d = want[i] - v[i]
            if abs(d) < 0.0015 { v[i] = want[i] } else { v[i] += d * k; moving = true }
        }
        shown = v
        var c = cables
        for i in c.indices {
            let live = s.cables.indices.contains(c[i].id) && s.cables[c[i].id] == c[i].cable
            let goal = live ? 1.0 : 0.0, d = goal - c[i].alpha
            if abs(d) < 0.02 { c[i].alpha = goal } else { c[i].alpha += d * min(1, dt / 0.08); moving = true }
        }
        cables = c.filter { $0.alpha > 0 || (s.cables.indices.contains($0.id) && s.cables[$0.id] == $0.cable) }
        return moving
    }
}

extension Layout {
    static let kinds: [Param: KnobKind] = Dictionary(uniqueKeysWithValues: knobs.map { ($0.param, $0.kind) })
    static func kind(_ p: Param) -> KnobKind { kinds[p] ?? .dial }
}
