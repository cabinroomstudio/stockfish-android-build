# Stockfish 11 for Android (arm64)

The source and build recipe for the Stockfish chess engine binary shipped in
Cabin Room Studio's Android chess puzzle app, published under the
GNU General Public License v3 (see `COPYING`).

The app runs this binary as a separate process for its computer opponent and
analysis. Everything needed to rebuild it is here.

## What is here

| File | What it is |
|---|---|
| `source/Stockfish-sf_11.tar.gz` | The official Stockfish 11 release source, unchanged, from `github.com/official-stockfish/Stockfish` (tag `sf_11`) |
| `build_stockfish_android.sh` | The exact build recipe: compiler, flags and the one added source file |
| `COPYING` | The GNU GPL v3, as shipped with Stockfish |

## Changes from the official release

No Stockfish source file is edited. The build adds one file,
`android_tls_align.cpp` (one line, written out by the script), which raises
the binary's TLS segment alignment to 64 bytes so Android's arm64 loader
will run it. The build flags are in the script.

## Build it

Needs bash, tar, sha256sum and the Android NDK r26.1.10909125
(set `ANDROID_NDK_HOME`, or have it at the default Android SDK location).

```bash
bash build_stockfish_android.sh out/libstockfish.so
```

The result is byte-identical to the binary in the app:

| File | Size | SHA-256 |
|---|---|---|
| `libstockfish.so` | 1,705,560 bytes | `8f47275303de75da183de5c9e99edf01651f2f6b9b1d2dce078e62018003ad10` |
| `source/Stockfish-sf_11.tar.gz` | 145,868 bytes | `802261cc601b67bed00c0ef7d21e2125959630f0852a06db9fc9bd74f440b199` |

Stockfish embeds its compile date; the script pins it with
`SOURCE_DATE_EPOCH` so the build reproduces.

## Credits

Stockfish is developed by the Stockfish developers (see `AUTHORS` in the
source archive) at https://stockfishchess.org. This repository adds only the
Android build recipe.
