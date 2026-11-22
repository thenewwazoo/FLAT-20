// SPDX-License-Identifier: GPL-3.0-only
// Offline PNG renderer for testing panel layout without the GUI app or an FM-1:
//   panel-render OUT.png LOG [MS] [WIDTH]
// Reads "SysEx out" lines from build/host/flat20 log output up to timestamp MS (default: end of log).
import AppKit
import SwiftUI
import FlatLink
import FlatPanelUI

@MainActor func run() -> Int32 {
    let a = CommandLine.arguments
    guard a.count >= 3 else { FileHandle.standardError.write("panel-render OUT.png LOG [MS] [WIDTH]\n".data(using: .utf8)!); return 2 }
    let until = a.count > 3 ? Int(a[3]) ?? Int.max : Int.max
    let width = a.count > 4 ? Double(a[4]) ?? 1545 : 1545
    guard let log = try? String(contentsOfFile: a[2], encoding: .utf8) else { return 1 }
    let model = PanelModel()
    model.animates = false
    var n = 0
    for line in log.split(separator: "\n") where line.contains("SysEx out") {
        let parts = line.split(separator: " ")
        guard let ms = Int(parts[0]), ms <= until else { continue }
        let bytes = parts.drop { $0 != "out" }.dropFirst().compactMap { UInt8($0, radix: 16) }
        model.receive(bytes, from: "host build", at: Date())
        n += 1
    }
    let view = PanelView(model: model).frame(width: width, height: width * 800 / 1545)
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return 1 }
    try? png.write(to: URL(fileURLWithPath: a[1]))
    print("\(n) messages, \(a[1])")
    return 0
}
exit(MainActor.assumeIsolated { run() })
