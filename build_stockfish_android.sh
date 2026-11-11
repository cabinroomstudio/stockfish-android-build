#!/usr/bin/env bash
#
# Builds the Stockfish 11 engine binary shipped in Cabin Room Studio's Android
# chess puzzle app as lib/arm64-v8a/libstockfish.so.
#
# This file is published, with the Stockfish source it builds, at
#   https://github.com/cabinroomstudio/stockfish-android-build
# to meet the GPLv3's Corresponding Source terms. Keep that copy and this one
# identical: the app's tests check this script and the shipped binary against
# the hashes in core StockfishLicence.kt.
#
#   bash build_stockfish_android.sh [output path]     (default ./libstockfish.so)
#
# The result is byte-identical to the shipped binary (SHA-256 in README.md):
# the compile date Stockfish embeds is pinned through SOURCE_DATE_EPOCH.
#
# Why Stockfish 11 and not a current release: modern Stockfish embeds an NNUE
# network, which made the binary 114 MB. The app's difficulty tiers top out at
# 2400 Elo and the engine runs at 1 thread / 16 MB hash / 1000 ms movetime.
# SF 11 is pre-NNUE, ~3400 Elo, 1.6 MB, and fast on mobile at these settings.
#
# What differs from the official sf_11 release: one added source file (the TLS
# shim below) and the build flags in this script. No Stockfish file is edited.
#
# If you change the Stockfish version, re-check the UCI_Elo min/max the engine
# advertises (SF 11: 1350-2850); out-of-range values are clamped silently.
#
# Requires curl, tar, sha256sum and the Android NDK (r26.1.10909125).

set -euo pipefail

SF_TAG="sf_11"
API_LEVEL=26            # the app's minSdk
NDK_VERSION="26.1.10909125"
NDK_ROOT="${ANDROID_NDK_HOME:-$LOCALAPPDATA/Android/Sdk/ndk/$NDK_VERSION}"

# Stockfish compiles __DATE__ into the binary (unused while Version is "11",
# but it changes the bytes). Pinning it to the day the shipped binary was
# built, 2026-09-06, makes the build reproducible.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1788696000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$PWD/libstockfish.so}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# On Windows the NDK ships .cmd wrappers; on Linux/macOS it does not.
TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt"
HOST_DIR="$(ls "$TOOLCHAIN" | head -1)"
BIN="$TOOLCHAIN/$HOST_DIR/bin"
CXX="$BIN/aarch64-linux-android$API_LEVEL-clang++"
[ -x "$CXX" ] || CXX="$CXX.cmd"
STRIP="$BIN/llvm-strip"
[ -x "$STRIP" ] || STRIP="$STRIP.exe"
READELF="$BIN/llvm-readelf"
[ -x "$READELF" ] || READELF="$READELF.exe"

# Use the source copy next to this script when there is one (the published
# repo carries it), else fetch the official release tag.
TARBALL="$SCRIPT_DIR/source/Stockfish-$SF_TAG.tar.gz"
if [ -f "$TARBALL" ]; then
  echo "==> Using bundled Stockfish $SF_TAG source"
  cp "$TARBALL" "$WORK/sf.tar.gz"
else
  echo "==> Fetching Stockfish $SF_TAG source"
  curl -sL -o "$WORK/sf.tar.gz" \
    "https://github.com/official-stockfish/Stockfish/archive/refs/tags/$SF_TAG.tar.gz"
fi
tar xzf "$WORK/sf.tar.gz" -C "$WORK"
SRC="$WORK/Stockfish-$SF_TAG/src"

# Bionic on arm64 refuses to exec a binary whose PT_TLS segment is aligned to
# less than 64 bytes ("executable's TLS segment is underaligned: alignment is
# 8, needs to be at least 64 for ARM64 Bionic"). NDK r26's static bionic
# contributes an 8-byte-aligned TLS segment and its lld does not round it up;
# r27+ does.
#
# The fix is one over-aligned thread_local, which raises the whole segment's
# alignment to 64. Two things here are load-bearing:
#   - -fno-emulated-tls is REQUIRED. Android defaults to emulated TLS on this
#     NDK, which routes thread_local through __emutls_* on the heap so the pad
#     never reaches the ELF TLS segment and the binary still won't run.
#   - `used` stops the linker dropping a variable nothing references.
cat > "$SRC/android_tls_align.cpp" <<'SHIM_EOF'
__attribute__((used)) alignas(64) thread_local char android_tls_align_pad[64] = { 1 };
SHIM_EOF

# SF 11 predates the Makefile's armv8 target, so drive the compiler directly.
# IS_64BIT and USE_POPCNT are what general-64 plus native aarch64 popcount
# amount to. -Wl,-z,max-page-size=16384 aligns the LOAD segments to 16 KB, which
# Google Play requires for apps targeting Android 15+.
echo "==> Cross-compiling for arm64-v8a (API $API_LEVEL)"
cd "$SRC"
"$CXX" \
  -O3 -std=c++11 -fno-exceptions -DNDEBUG -DIS_64BIT -DUSE_POPCNT \
  -fno-emulated-tls -static -pthread \
  -Wl,-z,max-page-size=16384 \
  -o "$WORK/stockfish" \
  benchmark.cpp bitbase.cpp bitboard.cpp endgame.cpp evaluate.cpp main.cpp \
  material.cpp misc.cpp movegen.cpp movepick.cpp pawns.cpp position.cpp \
  psqt.cpp search.cpp thread.cpp timeman.cpp tt.cpp uci.cpp ucioption.cpp \
  syzygy/tbprobe.cpp android_tls_align.cpp

echo "==> Stripping"
"$STRIP" -s "$WORK/stockfish" -o "$DEST"

echo "==> Done: $DEST"
ls -la "$DEST"
sha256sum "$DEST" 2>/dev/null || true

# This MUST read 0x40, or the binary will not run on any arm64 device.
echo "==> TLS segment alignment (must be 0x40):"
"$READELF" -l "$DEST" | grep -E "^  TLS" || true

# Must read 0x4000 on every LOAD segment, or Google Play rejects the bundle.
echo "==> LOAD segment alignment (must be 0x4000):"
"$READELF" -l "$DEST" | grep -E "^  LOAD" || true

cat <<'NOTE'

Expected: ELF 64-bit LSB executable, ARM aarch64, statically linked, stripped,
1,705,560 bytes. To smoke-test on a connected device:

  adb push <binary> /data/local/tmp/sf_test
  adb shell chmod 755 /data/local/tmp/sf_test
  adb shell "(echo uci; echo isready; echo 'position startpos'; \
              echo 'go movetime 1500'; sleep 3; echo quit) | /data/local/tmp/sf_test"

Expect uciok, readyok and a sensible bestmove around depth 15.
NOTE
