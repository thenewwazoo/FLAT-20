// SPDX-License-Identifier: GPL-3.0-only
// Patching with the mouse, as rules on the eight cable slots (no drawing, no MIDI: the panel and the app do those).
//   - Click a jack, then another: a cable between them. Any two jacks: the FM-1 wires them as the panel would be wired
//     (an output into an input as usual; two inputs or two outputs do what they would do on the instrument).
//   - The first click on a jack that has a cable pulls that cable out; the second click then plugs the new one in.
//   - The second click on a jack that has a cable pulls that one out too, before the new one goes in.
//   - Click a cable: it is gone, both ends.
//   - Option-click a jack: a dummy plug (a cable to nothing), which breaks the jack's internal connection and gives it
//     nothing instead; Option-click a jack with a plug in it: that cable comes out.
//   - The same jack twice, or Esc: nothing more happens (a cable pulled by the first click stays out, as a plug pulled
//     and put down would).
// One plug a jack, as on the MS-20's panel.
import FlatLink

public struct PatchEditor: Equatable, Sendable {
    /// the eight slots, as the FM-1 has them
    public var cables: [Cable?]
    /// the jack clicked first, waiting for the second click
    public var pending: JackID?

    public init(cables: [Cable?], pending: JackID? = nil) {
        self.cables = cables + Array(repeating: nil, count: max(0, LinkFormat.cables - cables.count))
        self.pending = pending
    }

    public enum Outcome: Equatable, Sendable {
        /// the cables changed: send them
        case changed
        /// nothing to send (a first click on a free jack, a cancel)
        case unchanged
        /// not allowed: why, for the screen
        case refused(String)
    }

    /// pulls the cable plugged into j, if any; true if there was one
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
