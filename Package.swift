// swift-tools-version: 6.0
import PackageDescription

// Upstream signalapp/libsignal version this release tracks. Keep in sync with the tag,
// the `SignalFfi` binaryTarget URL, and Sources/LibSignalClient (all set by scripts/build-xcframework.sh).
let libsignalVersion = "0.105.0"

let package = Package(
    name: "LibSignalClient",
    // The binary is built for iOS 15 (upstream build_ffi.sh) and macOS 11 arm64 (build-xcframework.sh).
    platforms: [.iOS(.v15), .macOS(.v11)],
    products: [
        .library(name: "LibSignalClient", targets: ["LibSignalClient"]),
    ],
    targets: [
        // Prebuilt Rust FFI (BoringSSL + libsignal), built from source with NO bitcode so it can be
        // packaged as an xcframework (Signal's own prebuilt cannot). Produced + uploaded by CI.
        .binaryTarget(
            name: "SignalFfi",
            url: "https://github.com/jonathan132c/libsignal-client-swift/releases/download/0.105.0/SignalFfi.xcframework.zip",
            checksum: "b2b426deb0c0f59d5030d0b13b079203f31db110be14c194d32ad352b8c3b54d" // set by scripts/build-xcframework.sh
        ),
        .target(
            name: "LibSignalClient",
            dependencies: ["SignalFfi"],
            path: "Sources/LibSignalClient",
            // as upstream swift/Package.swift
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
