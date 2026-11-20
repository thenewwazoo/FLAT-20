// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-only
// FLAT-20 Panel: the FM-1's MS-20 emulation as a panel on the Mac (one way: it listens, it never sends).
import PackageDescription

let package = Package(
    name: "FLAT20Panel",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FlatLink"),
        .target(name: "FlatPanelUI", dependencies: ["FlatLink"]),
        .executableTarget(name: "FLAT20Panel", dependencies: ["FlatLink", "FlatPanelUI"]),
        .executableTarget(name: "panel-render", dependencies: ["FlatLink", "FlatPanelUI"]),
        .testTarget(name: "FlatLinkTests", dependencies: ["FlatLink", "FlatPanelUI"], resources: [.copy("Fixtures")]),
    ]
)
