// SPDX-License-Identifier: GPL-3.0-only
// FLAT-20 Panel: macOS companion app displaying live FM-1 state over USB MIDI and supporting mouse patching.
import AppKit
import SwiftUI
import FlatLink
import FlatPanelUI

@main
struct FLAT20PanelApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    @State private var model = PanelModel()
    @State private var listener: MIDIListener?
    @State private var problem: String?

    var body: some Scene {
        Window("FLAT-20", id: "panel") {
            PanelView(model: model)
                .frame(minWidth: 780, minHeight: 404)
                .background {
                    Button("Put the loose cable down") { model.cancelPatching() }
                        .keyboardShortcut(.cancelAction)                     // Esc
                        .opacity(0).frame(width: 0, height: 0)
                }
                .overlay(alignment: .top) {
                    if let problem { Text(problem).padding(8).background(.red.opacity(0.8)).foregroundStyle(.white) }
                }
                .task { start() }
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(500))
                        model.tick()
                    }
                }
                .task { await snapshots() }
                .task { await scriptedClicks() }
        }
        .defaultSize(width: 1545 * 0.85, height: 800 * 0.85)
        .windowResizability(.contentMinSize)
    }

    /// FLAT20_SNAPSHOT=/some/prefix: the panel as PNG every 2 s (prefix-0001.png, ...), for checking the app without a screen
    func snapshots() async {
        guard let prefix = ProcessInfo.processInfo.environment["FLAT20_SNAPSHOT"] else { return }
        var n = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            n += 1
            let r = ImageRenderer(content: PanelView(model: model).frame(width: 1545, height: 800))
            if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: String(format: "%@-%04d.png", prefix, n)))
            }
        }
    }

    /// FLAT20_CLICKS="out:eg2Rev in:total cable:0 din:trig ...": clicks on those jacks or cable slots (din: / dout: an
    /// Option-click on an input / output), 0.7 s apart, once the FM-1
    /// can be patched: the mouse's path from the hit test on, for checking the app against an FM-1 without a hand on it
    func scriptedClicks() async {
        guard let script = ProcessInfo.processInfo.environment["FLAT20_CLICKS"] else { return }
        while !model.canPatch { try? await Task.sleep(for: .milliseconds(200)) }
        for word in script.split(separator: " ") {
            try? await Task.sleep(for: .milliseconds(700))
            let p = word.split(separator: ":"), name = p.count > 1 ? String(p[1]) : ""
            var kind = p.first ?? ""
            let option = kind.hasPrefix("d") && kind.count > 2
            if option { kind = kind.dropFirst() }
            var at: CGPoint?
            if kind == "out", let s = Source.allCases.first(where: { "\($0)" == name }) { at = Layout.jack(.output(s))?.center }
            if kind == "in", let d = Destination.allCases.first(where: { "\($0)" == name }) { at = Layout.jack(.input(d))?.center }
            if kind == "cable", let i = Int(name), let c = model.cables.first(where: { $0.id == i }), let (path, _, _) = Hit.pathPoint(c, model.cables) { at = path }
            if let at { model.click(at: at, option: option) } else { print("FLAT20_CLICKS: what is \(word)?") }
        }
    }

    func start() {
        guard listener == nil else { return }
        let m = model
        let l = MIDIListener { bytes, source in
            Task { @MainActor in m.receive(bytes, from: source) }
        }
        do { try l.start(); listener = l } catch { problem = "CoreMIDI would not start: \(error)" }
        model.send = { [l] bytes in l.send(bytes) }
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)                      // (also when run as a bare executable)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}
