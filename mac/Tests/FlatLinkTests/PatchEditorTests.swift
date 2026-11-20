// SPDX-License-Identifier: GPL-3.0-only
// Patching with the mouse: the rules as the player asked for them.
import Testing
@testable import FlatLink
@testable import FlatPanelUI

let mgTri = JackID.output(.mgTri), mgRect = JackID.output(.mgRect), white = JackID.output(.white)
let total = JackID.input(.total), trig = JackID.input(.trig), shIn = JackID.input(.shIn)

@Test func twoClicksMakeACableEitherWayRound() {
    var e = PatchEditor(cables: [])
    #expect(e.click(mgTri) == .unchanged && e.pending == mgTri)
    #expect(e.click(total) == .changed && e.pending == nil)
    #expect(e.cables[0] == Cable(source: .mgTri, destination: .total))
    #expect(e.click(trig) == .unchanged)                       // the input first this time
    #expect(e.click(mgRect) == .changed)
    #expect(e.cables[1] == Cable(source: .mgRect, destination: .trig))
}

@Test func firstClickOnAPluggedJackPullsItsCableThenTheSecondPlugsTheNewOne() {
    var e = PatchEditor(cables: [Cable(source: .mgTri, destination: .total)])
    #expect(e.click(mgTri) == .changed)                       // pulled at once
    #expect(e.cables.allSatisfy { $0 == nil } && e.pending == mgTri)
    #expect(e.click(shIn) == .changed)
    #expect(e.cables.compactMap { $0 } == [Cable(source: .mgTri, destination: .shIn)])
}

@Test func secondClickOnAPluggedJackPullsThatCableFirst() {
    var e = PatchEditor(cables: [Cable(source: .white, destination: .total)])
    _ = e.click(mgTri)
    #expect(e.click(total) == .changed)
    #expect(e.cables.compactMap { $0 } == [Cable(source: .mgTri, destination: .total)])
}

@Test func clickingACableRemovesBothEnds() {
    var e = PatchEditor(cables: [Cable(source: .white, destination: .total), Cable(source: .mgRect, destination: .trig)])
    #expect(e.clickCable(0) == .changed)
    #expect(e.cables[0] == nil && e.cables[1] == Cable(source: .mgRect, destination: .trig))
    #expect(e.clickCable(0) == .unchanged)
}

@Test func sameJackTwiceIsACancelAndAPulledCableStaysOut() {
    var e = PatchEditor(cables: [Cable(source: .white, destination: .total)])
    #expect(e.click(white) == .changed)
    #expect(e.click(white) == .unchanged && e.pending == nil)
    #expect(e.cables.allSatisfy { $0 == nil })
}

@Test func twoOutputsOrTwoInputsAreJoinedAsOnThePanel() {
    var e = PatchEditor(cables: [])
    _ = e.click(mgTri)
    #expect(e.click(white) == .changed && e.cables[0] == Cable(mgTri, white))
    _ = e.click(trig)
    #expect(e.click(shIn) == .changed && e.cables[1] == Cable(trig, shIn))
}

@Test func optionClickPutsADummyPlugInAndTakesAPlugOut() {
    var e = PatchEditor(cables: [Cable(source: .white, destination: .total)])
    #expect(e.dummy(trig) == .changed && e.cables[1] == Cable(trig, nil))
    #expect(e.dummy(trig) == .changed && e.cables[1] == nil)                  // again: out
    #expect(e.dummy(total) == .changed && e.cables.allSatisfy { $0 == nil })    // a real cable's jack: that cable out
    _ = e.click(mgTri)                                                          // a pending first click is put down
    #expect(e.dummy(shIn) == .changed && e.pending == nil)
    // a dummy plug's jack clicked first: the dummy comes out, the jack waits for its new cable
    #expect(e.click(shIn) == .changed && e.pending == shIn && e.cables.allSatisfy { $0 == nil })
    #expect(e.click(white) == .changed && e.cables[0] == Cable(shIn, white))
}

@Test func nineCablesDoNotFit() {
    let srcs: [Source] = [.kbdCv, .kbdTrig, .mgTri, .mgRect, .eg1, .eg1Rev, .eg2Rev, .sh]
    let dsts: [Destination] = [.total, .freq, .vcoCv, .vco2Cv, .extIn, .hpCut, .lpCut, .gain]
    var e = PatchEditor(cables: zip(srcs, dsts).map { Cable(source: $0, destination: $1) })
    _ = e.click(white)
    if case .refused = e.click(trig) {} else { Issue.record("a ninth cable") }
    #expect(e.cables.compactMap { $0 }.count == 8 && e.pending == nil)
    // ... but replacing one does: the second click's own cable comes out first
    _ = e.click(white)
    #expect(e.click(.input(.total)) == .changed)
    #expect(e.cables.contains(Cable(source: .white, destination: .total)))
}

@Test func theCablesMessageIsWhatTheFirmwareReads() {
    let m = LinkEncoder.cables([Cable(source: .white, destination: .shIn), nil, Cable(source: .mgRect, destination: .shClock)])
    // ms20_link.h: F0 7D 46 32 30 VER 03 NSRC NDST (jack jack) x 8 F7; a jack: the outputs from 1, then the inputs
    let ns = Source.allCases.count
    #expect(m.count == 7 + 2 + 2 * LinkFormat.cables + 1)
    #expect(Array(m.prefix(9)) == [0xF0, 0x7D, 0x46, 0x32, 0x30, LinkFormat.version, 3, UInt8(ns), UInt8(Destination.allCases.count)])
    #expect(Array(m[9..<15]).map(Int.init) == [Source.white.rawValue, ns - 1 + Destination.shIn.rawValue, 0, 0, Source.mgRect.rawValue, ns - 1 + Destination.shClock.rawValue])
    let d = LinkEncoder.cables([Cable(trig, nil)])
    #expect(Int(d[9]) == ns - 1 + Destination.trig.rawValue && d[10] == 0)
    for j in Source.allCases.dropFirst().map(JackID.output) + Destination.allCases.dropFirst().map(JackID.input) {
        #expect(JackID(number: j.number) == j)
    }
    #expect(m.last == 0xF7 && m.dropFirst().dropLast().allSatisfy { $0 < 0x80 })
}

@MainActor @Test func theModelSendsAndShowsAtOnce() throws {
    let ms = try fixtureMessages()
    let m = PanelModel(); m.animates = false
    var sent: [[UInt8]] = []
    m.send = { sent.append($0); return true }
    m.receive(ms[0].bytes, from: "x")
    #expect(m.canPatch)
    // FLAT BEAT: EG2 REV OUT -> LP CUTOFF. Click EG2 REV OUT (pulls it), then TOTAL
    let rev = try #require(Layout.jack(.output(.eg2Rev))).center, tot = try #require(Layout.jack(.input(.total))).center
    m.click(at: rev)
    #expect(sent.count == 1 && m.state?.cables.allSatisfy { $0 == nil } == true)
    m.click(at: tot)
    #expect(sent.count == 2 && m.state?.cables[0] == Cable(source: .eg2Rev, destination: .total))
}
