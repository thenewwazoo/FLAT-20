// SPDX-License-Identifier: GPL-3.0-only
// Listens to all CoreMIDI sources, tracks hot-plugged devices, and routes FLAT-20 SysEx packets.
// Only sends outgoing CABLES messages back to the active FM-1 endpoint when requested by the user.
import CoreMIDI
import Foundation
import Synchronization
import FlatLink

final class MIDIListener: Sendable {
    private let client = Mutex<MIDIClientRef>(0)
    private let port = Mutex<MIDIPortRef>(0)
    private let outPort = Mutex<MIDIPortRef>(0)
    /// Endpoint that last sent a valid FLAT-20 SysEx message.
    private let flat = Mutex<MIDIEndpointRef>(0)
    private let assemblers = Mutex<[MIDIEndpointRef: SysExAssembler]>([:])
    private let connected = Mutex<Set<MIDIEndpointRef>>([])
    private let deliver: @Sendable ([UInt8], String) -> Void

    /// Called on CoreMIDI's thread with each complete SysEx packet and its source name.
    init(deliver: @escaping @Sendable ([UInt8], String) -> Void) { self.deliver = deliver }

    func start() throws {
        var c: MIDIClientRef = 0
        var s = MIDIClientCreateWithBlock("FLAT-20 Panel" as CFString, &c) { [weak self] n in
            if n.pointee.messageID == .msgSetupChanged { self?.connectAll() }
        }
        guard s == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(s)) }
        client.withLock { $0 = c }
        var p: MIDIPortRef = 0
        s = MIDIInputPortCreateWithProtocol(c, "in" as CFString, ._1_0, &p) { [weak self] list, ref in
            self?.receive(list, from: MIDIEndpointRef(UInt(bitPattern: ref)))
        }
        guard s == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(s)) }
        port.withLock { $0 = p }
        var o: MIDIPortRef = 0
        s = MIDIOutputPortCreate(c, "out" as CFString, &o)
        guard s == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(s)) }
        outPort.withLock { $0 = o }
        connectAll()
    }

    /// the FM-1's own input: the destination beside the source it is heard on (its USB device's), or one of the same name
    func destination() -> MIDIEndpointRef? {
        let src = flat.withLock { $0 }
        guard src != 0 else { return nil }
        var entity: MIDIEntityRef = 0
        if MIDIEndpointGetEntity(src, &entity) == noErr, entity != 0, MIDIEntityGetNumberOfDestinations(entity) > 0 {
            let d = MIDIEntityGetDestination(entity, 0)
            if d != 0 { return d }
        }
        let name = Self.name(src)
        return (0..<MIDIGetNumberOfDestinations()).map { MIDIGetDestination($0) }.first { $0 != 0 && Self.name($0) == name }
    }

    /// one SysEx message (F0 ... F7) to the FM-1, as Universal MIDI Packets; false if there is no FM-1 to send it to
    func send(_ m: [UInt8]) -> Bool {
        guard m.count >= 2, m.first == 0xF0, m.last == 0xF7, let dest = destination() else { return false }
        let o = outPort.withLock { $0 }
        let body = Array(m.dropFirst().dropLast())
        var words: [UInt32] = []
        var i = 0
        while i < body.count || (i == 0 && body.isEmpty) {
            let n = min(6, body.count - i), first = i == 0, last = i + n >= body.count
            let status: UInt32 = first && last ? 0 : first ? 1 : last ? 3 : 2
            var b = [UInt8](repeating: 0, count: 6)
            for k in 0..<n { b[k] = body[i + k] }
            words.append(0x3 << 28 | status << 20 | UInt32(n) << 16 | UInt32(b[0]) << 8 | UInt32(b[1]))
            words.append(UInt32(b[2]) << 24 | UInt32(b[3]) << 16 | UInt32(b[4]) << 8 | UInt32(b[5]))
            i += max(n, 1)
            if body.isEmpty { break }
        }
        let size = 1024
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var pkt = MIDIEventListInit(list, ._1_0)
        var k = 0
        while k < words.count {
            pkt = words[k...].prefix(2).withUnsafeBufferPointer { MIDIEventListAdd(list, size, pkt, 0, $0.count, $0.baseAddress!) }
            k += 2
        }
        return MIDISendEventList(o, dest, list) == noErr
    }

    /// connects every source not yet connected (a source that went away is gone from CoreMIDI's list by itself)
    func connectAll() {
        let p = port.withLock { $0 }
        guard p != 0 else { return }
        let now = Set((0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }.filter { $0 != 0 })
        connected.withLock { have in
            for src in now.subtracting(have) {
                MIDIPortConnectSource(p, src, UnsafeMutableRawPointer(bitPattern: UInt(src)))
            }
            have = now
        }
        assemblers.withLock { a in a = a.filter { now.contains($0.key) } }
    }

    static func name(_ e: MIDIEndpointRef) -> String {
        var n: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &n)
        return (n?.takeRetainedValue() as String?) ?? "MIDI source \(e)"
    }

    /// Universal MIDI Packets to a MIDI 1.0 byte stream (only what can carry SysEx matters here)
    private func receive(_ list: UnsafePointer<MIDIEventList>, from src: MIDIEndpointRef) {
        var bytes: [UInt8] = []
        for packet in list.unsafeSequence() {
            let n = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let w = raw.bindMemory(to: UInt32.self)
                var i = 0
                while i < n {
                    let w0 = w[i], type = w0 >> 28
                    let size = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4][Int(type)]
                    if type == 3, i + 1 < n {               // a 64-bit data message: up to 6 bytes of SysEx
                        let status = (w0 >> 20) & 0xF, count = Int((w0 >> 16) & 0xF)
                        let all: [UInt8] = [UInt8(w0 >> 8 & 0x7F), UInt8(w0 & 0x7F), UInt8(w[i + 1] >> 24 & 0x7F),
                                            UInt8(w[i + 1] >> 16 & 0x7F), UInt8(w[i + 1] >> 8 & 0x7F), UInt8(w[i + 1] & 0x7F)]
                        if status == 0 || status == 1 { bytes.append(0xF0) }
                        bytes.append(contentsOf: all.prefix(min(6, count)))
                        if status == 0 || status == 3 { bytes.append(0xF7) }
                    } else if type == 2 || type == 1 {
                        let st = UInt8(w0 >> 16 & 0xFF)
                        if st < 0xF8 { bytes.append(st) }   // (a status byte ends any unfinished SysEx; realtime does not)
                    }
                    i += size
                }
            }
        }
        guard !bytes.isEmpty else { return }
        let done = assemblers.withLock { a in
            var asm = a[src] ?? SysExAssembler()
            let out = asm.feed(bytes)
            a[src] = asm
            return out
        }
        if done.isEmpty { return }
        let name = Self.name(src)
        for m in done {
            if m.count > 5, m[1] == LinkFormat.id, m[2] == 0x46, m[3] == 0x32, m[4] == 0x30 { flat.withLock { $0 = src } }
            deliver(m, name)
        }
    }
}
