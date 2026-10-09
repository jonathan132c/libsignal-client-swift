# LibSignalClient-SPM

> **Fork note (jonathan132c/libsignal-client-swift).** Forked from
> [david2701/LibSignalClient-SPM](https://github.com/david2701/LibSignalClient-SPM) for the msgr iOS app.
> Changes: the xcframework also carries a **macOS arm64** slice (so dependents build and test with
> plain `swift build` / `swift test`), the build script reads the stable toolchain libsignal pins since
> 0.10x, and the manifest matches upstream (tools 6.0, strict concurrency, iOS 15 / macOS 11).
> Use `.package(url: "https://github.com/jonathan132c/libsignal-client-swift", exact: "<libsignal version>")`.

**Unofficial Swift Package Manager (SPM) distribution of [signalapp/libsignal](https://github.com/signalapp/libsignal)'s `LibSignalClient`.**

Signal only supports LibSignalClient via **CocoaPods** — [its docs say SPM "is not supported"](https://github.com/signalapp/libsignal/blob/main/swift/README.md), and Signal's prebuilt `libsignal_ffi.a` embeds bitcode (from BoringSSL) so it can't be wrapped in an `.xcframework`. This mirror closes that gap: CI builds the Rust FFI **from source with no bitcode**, packages it as an `.xcframework`, and publishes it as a release asset that a plain SPM `binaryTarget` can consume.

> Not affiliated with or endorsed by Signal. Use at your own risk. The cryptographic code is Signal's, built unmodified from the pinned upstream tag.

## Install

Add the package (pin to the upstream libsignal version tag, e.g. `0.79.1`):

```swift
.package(url: "https://github.com/david2701/LibSignalClient-SPM.git", exact: "0.79.1")
```

or in Xcode: **File → Add Package Dependencies →** `https://github.com/david2701/LibSignalClient-SPM` → *Exact Version* `0.79.1`. Then `import LibSignalClient`.

Available versions = tags on this repo (each tracks the same upstream `signalapp/libsignal` version).

## How it works

- `Sources/LibSignalClient/` — the upstream Swift sources, verbatim, at the pinned version.
- `SignalFfi` — a `binaryTarget` pointing at `SignalFfi.xcframework.zip` in this repo's Releases (built from source, device + simulator, arm64 + x86_64, **no bitcode**).
- `scripts/build-xcframework.sh` — reproducible build (clone upstream → `build_ffi.sh` per iOS target → `lipo` → `create-xcframework` → checksum → patch `Package.swift`).
- `.github/workflows/build-and-release.yml` — runs the script on a macOS runner, uploads the asset, syncs sources, and tags.

## Bump to a new upstream version

Run the **Build & release** workflow (Actions tab) with the new libsignal version, or locally:

```bash
scripts/build-xcframework.sh 0.80.0   # requires rustup + iOS targets, protoc, Xcode
# then commit the synced Sources/ + Package.swift, tag 0.80.0, and upload build/SignalFfi.xcframework.zip to a release
```

## License

`LibSignalClient` and the FFI are Signal's, licensed **AGPL-3.0-only** — see [`LICENSE`](LICENSE). This mirror redistributes them unmodified and adds only packaging (also AGPL-3.0-only). Upstream source: https://github.com/signalapp/libsignal
