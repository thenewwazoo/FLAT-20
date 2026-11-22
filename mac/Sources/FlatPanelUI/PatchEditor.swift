// SPDX-License-Identifier: GPL-3.0-only
// Pure state machine for mouse patching across the 8 cable slots (no UI or MIDI).
// Rules (one plug per jack, matching hardware):
//   - Click jack A then jack B: connect A and B (any jack types allowed; FM-1 solves the circuit).
//   - Clicking an occupied jack unplugs its existing cable first.
//   - Clicking a cable unplugs both ends.
//   - Option-click an empty jack: insert a dummy plug (breaks internal normal). Option-click an occupied jack: unplug.
//   - Clicking the same jack twice or pressing Esc cancels (any cable already unplugged stays unplugged).
import FlatLink

public struct PatchEditor: Equatable, Sendable {
    /// Eight cable slots matching the FM-1's patch table.
    public var cables: [Cable?]
    /// First clicked jack awaiting a second click.
    public var pending: JackID?

    public init(cables: [Cable?], pending: JackID? = nil) {
        self.cables = cables + Array(repeating: nil, count: max(0, LinkFormat.cables - cables.count))
        self.pending = pending
    }

    public enum Outcome: Equatable, Sendable {
        /// Cable table changed; send CABLES SysEx.
        case changed
        /// No cable table change (e.g., first click on empty jack or cancel).
        case unchanged
        /// Action rejected, with reason to display.
        case refused(String)
    }

    /// Unplugs any cable connected to `j`; returns true if one was removed.
    mutating func pull(_ j: JackID) -> Bool {
        var any = false
        for i in cables.indices where cables[i]?.touches(j) == true {
            cables[i] = nil
            any = true
        }
        return any
    }

    var full: Outcome { .refused("All \(LinkFormat.cables) cables are in use: click one to pull it out") }

    public mutating func click(_ j: JackID) -> Outcome {
        guard let first = pending else {
            pending = j
            return pull(j) ? .changed : .unchanged
        }
        pending = nil
        if first == j { return .unchanged }
        let pulled = pull(j)
        guard let slot = cables.firstIndex(where: { $0 == nil }) else { return pulled ? .changed : full }
        cables[slot] = Cable(first, j)
        return .changed
    }

    /// Option-click: a dummy plug into j, or j's cable out if it has one
    public mutating func dummy(_ j: JackID) -> Outcome {
        pending = nil
        if pull(j) { return .changed }
        guard let slot = cables.firstIndex(where: { $0 == nil }) else { return full }
        cables[slot] = Cable(j, nil)
        return .changed
    }

    /// a click on cable slot i: it comes out, both ends
    public mutating func clickCable(_ i: Int) -> Outcome {
        guard cables.indices.contains(i), cables[i] != nil else { return .unchanged }
        cables[i] = nil
        return .changed
    }

    public mutating func cancel() { pending = nil }
}
