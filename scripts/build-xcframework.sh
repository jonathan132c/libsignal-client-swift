#!/usr/bin/env bash
# Build SignalFfi.xcframework from upstream signalapp/libsignal SOURCE (no bitcode → xcframework-able),
# sync the matching Swift sources + FFI headers, produce the zip, and patch Package.swift with the
# release URL + SPM checksum. Reproducible; run in CI (macOS) or locally.
#
#   Usage: scripts/build-xcframework.sh <libsignal-version>   e.g. 0.79.1
#
# Requires: rustup (+ iOS targets), protoc, Xcode (xcodebuild/lipo), swift.
set -euo pipefail

VERSION="${1:?usage: build-xcframework.sh <version, e.g. 0.79.1>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWNER_REPO="${GITHUB_REPOSITORY:-jonathan132c/libsignal-client-swift}"
OUT="$REPO_ROOT/build"; rm -rf "$OUT"; mkdir -p "$OUT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "==> cloning signalapp/libsignal v$VERSION"
# The release tags are annotated; a shallow clone's auto-checkout errors ("is not a commit") and
# leaves an empty tree, so check out the tag explicitly after cloning.
git clone --no-checkout --depth 1 --branch "v${VERSION}" https://github.com/signalapp/libsignal "$WORK/ls"
cd "$WORK/ls"
git checkout "v${VERSION}"
test -f swift/build_ffi.sh || { echo "checkout failed: no swift/build_ffi.sh"; exit 1; }

# libsignal pins its toolchain in `rust-toolchain` (no .toml): a nightly up to 0.79, a plain stable
# version such as 1.98.1 by 0.105. Install whichever it names + the Apple targets FOR IT.
TC_FILE="rust-toolchain"; [ -f "$TC_FILE" ] || TC_FILE="rust-toolchain.toml"
TOOLCHAIN="$(grep -oE 'nightly-[0-9-]+|[0-9]+\.[0-9]+(\.[0-9]+)?' "$TC_FILE" | head -1)"
[ -n "$TOOLCHAIN" ] || { echo "no toolchain found in $TC_FILE"; exit 1; }
echo "==> rust toolchain: $TOOLCHAIN"
rustup toolchain install "$TOOLCHAIN" --profile minimal

# libsignal's iOS build uses full LTO, which emits LLVM-bitcode objects that
# `xcodebuild -create-xcframework` cannot read (Unknown header 0xb17c0de). Disable LTO so the
# static lib is plain Mach-O (larger, but xcframework-able). This is the whole reason the mirror exists.
# Also drop -DOPENSSL_SMALL: with LTO off it leaves ring's p256 *_vartime functions undefined (they
# were eliminated/resolved under fat LTO) → consumer link fails with "Undefined _ring_core_...p256_point_mul_base_vartime".
perl -i -pe 's/CARGO_PROFILE_RELEASE_LTO=fat/CARGO_PROFILE_RELEASE_LTO=off/; s/-flto=full //g; s/-DOPENSSL_SMALL //g;' swift/build_ffi.sh

# aarch64-apple-darwin: the macOS slice, so a package that depends on this one still builds and
# tests with plain `swift build` / `swift test` on an Apple-silicon Mac or CI runner (no simulator).
# build_ffi.sh applies LTO only to -ios targets, so the macOS lib is plain Mach-O already.
export MACOSX_DEPLOYMENT_TARGET=11.0
TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin)
rustup target add --toolchain "$TOOLCHAIN" "${TARGETS[@]}"
for t in "${TARGETS[@]}"; do
  echo "==> building libsignal_ffi for $t (no LTO)"
  CARGO_BUILD_TARGET="$t" swift/build_ffi.sh --release
done

echo "==> fat simulator slice"
lipo -create \
  "target/aarch64-apple-ios-sim/release/libsignal_ffi.a" \
  "target/x86_64-apple-ios/release/libsignal_ffi.a" \
  -output "$WORK/libsignal_ffi_sim.a"

echo "==> headers (this version's SignalFfi module)"
HDRS="$WORK/headers"; mkdir -p "$HDRS"
cp swift/Sources/SignalFfi/signal_ffi.h swift/Sources/SignalFfi/signal_ffi_testing.h \
   swift/Sources/SignalFfi/module.modulemap "$HDRS/"

echo "==> create SignalFfi.xcframework"
rm -rf "$OUT/SignalFfi.xcframework"
xcodebuild -create-xcframework \
  -library "target/aarch64-apple-ios/release/libsignal_ffi.a" -headers "$HDRS" \
  -library "$WORK/libsignal_ffi_sim.a" -headers "$HDRS" \
  -library "target/aarch64-apple-darwin/release/libsignal_ffi.a" -headers "$HDRS" \
  -output "$OUT/SignalFfi.xcframework"

echo "==> zip + checksum"
( cd "$OUT" && zip -qry SignalFfi.xcframework.zip SignalFfi.xcframework )
CHECKSUM="$(swift package --package-path "$REPO_ROOT" compute-checksum "$OUT/SignalFfi.xcframework.zip")"
echo "checksum=$CHECKSUM"

echo "==> sync Swift sources + headers for v$VERSION into the mirror"
rm -rf "$REPO_ROOT/Sources/LibSignalClient" && mkdir -p "$REPO_ROOT/Sources/LibSignalClient"
cp -R swift/Sources/LibSignalClient/. "$REPO_ROOT/Sources/LibSignalClient/"
rm -rf "$REPO_ROOT/ffi-headers" && mkdir -p "$REPO_ROOT/ffi-headers" && cp "$HDRS"/* "$REPO_ROOT/ffi-headers/"

echo "==> patch Package.swift (version + url + checksum)"
URL="https://github.com/${OWNER_REPO}/releases/download/${VERSION}/SignalFfi.xcframework.zip"
python3 - "$REPO_ROOT/Package.swift" "$VERSION" "$URL" "$CHECKSUM" <<'PY'
import re, sys
path, version, url, checksum = sys.argv[1:5]
s = open(path).read()
s = re.sub(r'let libsignalVersion = "[^"]*"', f'let libsignalVersion = "{version}"', s)
s = re.sub(r'url: "[^"]*"', f'url: "{url}"', s)
s = re.sub(r'checksum: "[0-9a-f]{64}"', f'checksum: "{checksum}"', s)
open(path, "w").write(s)
PY

echo "DONE. Artifact: $OUT/SignalFfi.xcframework.zip  checksum=$CHECKSUM"
