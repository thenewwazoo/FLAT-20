// SPDX-License-Identifier: GPL-3.0-only
// The decoder against what the firmware really sends: Fixtures/host.log is build/host/dinghy's output for
// Fixtures/host-script.txt (tools/gen_link_fixture.sh makes both).
import Foundation
import Testing
@testable import FlatLink
@testable import FlatPanelUI

func fixtureMessages() throws -> [(ms: Int, bytes: [UInt8])] {
    let url = try #require(Bundle.module.url(forResource: "host", withExtension: "log", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").compactMap { line in
        guard line.contains("SysEx out") else { return nil }
        let p = line.split(separator: " ")
        return (Int(p[0])!, p.drop { $0 != "out" }.dropFirst().compactMap { UInt8($0, radix: 16) })
    }
}

@Test func everyMessageFromTheFirmwareDecodes() throws {
    let ms = try fixtureMessages()
    #expect(ms.count > 20)
    for m in ms { _ = try LinkDecoder.decode(m.bytes) }
}

@Test func bootStateIsFlatBeat() throws {
    let first = try #require(try fixtureMessages().first { $0.bytes[6] == LinkFormat.state })
    guard case .state(let s) = try LinkDecoder.decode(first.bytes) else { Issue.record("not a STATE"); return }
    #expect(s.name == "FLAT BEAT" && s.preset == 1 && s.octave == 0 && !s.hold && !s.edited)
    #expect(s.position(.v1wave) == 2 && s.position(.v1scale) == 0)
    #expect(s.cables[0] == Cable(source: .eg2Rev, destination: .lpCut))
    #expect(s.cables.dropFirst().allSatisfy { $0 == nil })
}

@Test func programChangeBringsTheSandHPatch() throws {
    let states = try fixtureMessages().compactMap { m -> PatchState? in
        if case .state(let s) = try? LinkDecoder.decode(m.bytes) { return s } else { return nil }
    }
    let sh = try #require(states.first { $0.name == "S&H RANDOM" })
    #expect(sh.preset == 6)
    #expect(Set(sh.cables.compactMap { $0 }) == [Cable(source: .white, destination: .shIn), Cable(source: .mgRect, destination: .shClock), Cable(source: .sh, destination: .total)])
}

@Test func liveFollowsTheKey() throws {
    let lives = try fixtureMessages().compactMap { m -> LiveState? in
        if case .live(let l) = try? LinkDecoder.decode(m.bytes) { return l } else { return nil }
    }
    #expect(lives.contains { $0.gate && $0.note == 53 })
    #expect(lives.contains { $0.wheel != 0 })
}

@Test func otherSysExIsNotOurs() {
    #expect(throws: LinkError.notOurs) { try LinkDecoder.decode([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]) }
    #expect(throws: LinkError.notOurs) { try LinkDecoder.decode([0xF0, 0x22, 0x24, 0x35, 0x7D, 0xF7]) }
}

@Test func anotherFormatIsReportedNotDrawn() throws {
    var m = try #require(try fixtureMessages().first { $0.bytes[6] == LinkFormat.state }).bytes
    m[5] = LinkFormat.version + 1
    #expect { try LinkDecoder.decode(m) } throws: { e in if case LinkError.incompatible = e { return true } else { return false } }
    m[5] = LinkFormat.version; m[7] = 35
    #expect { try LinkDecoder.decode(m) } throws: { e in if case LinkError.incompatible = e { return true } else { return false } }
}

@Test func assemblerCopesWithSplitsRealtimeAndAborts() {
    var a = SysExAssembler()
    #expect(a.feed([0xF0, 0x01, 0xF8, 0x02]).isEmpty)          // a clock byte inside
    #expect(a.feed([0x03, 0xF7]) == [[0xF0, 0x01, 0x02, 0x03, 0xF7]])
    #expect(a.feed([0xF0, 0x01, 0x90, 0x40, 0x40, 0xF7]).isEmpty)   // a note-on ends it unfinished
    #expect(a.feed([0x01, 0x02]).isEmpty)
}

@MainActor @Test func modelGoesQuietAfterSilence() throws {
    let ms = try fixtureMessages()
    let m = PanelModel(); m.animates = false
    let t0 = Date()
    m.receive(ms[0].bytes, from: "x", at: t0)
    #expect(m.connected)
    m.tick(now: t0.addingTimeInterval(2.0)); #expect(m.connected)
    m.tick(now: t0.addingTimeInterval(3.0)); #expect(!m.connected)
}

@MainActor @Test func everyCableEndHasAJackOnThePanel() {
    for s in Source.allCases where s != .none { #expect(Layout.jack(.output(s)) != nil, "no jack for \(s)") }
    for d in Destination.allCases where d != .none { #expect(Layout.jack(.input(d)) != nil, "no jack for \(d)") }
    #expect(Set(Layout.knobs.map(\.param)) == Set(Param.allCases))
}
