# ChessCoach for Android

A Kotlin/Jetpack Compose port of ChessCoach, living entirely under `android/` so it
doesn't touch the existing Swift app (`Sources/`, `Apps/`). Same contract as iOS:
**Stockfish computes, nothing else does.** This build ships the **review tier
only** — engine play, grading, hints, puzzles, lessons, and the opening trainer,
all on-device. There is no Pro/coach tier here (no LLM prose, no subscription,
no BYOK/managed-coach settings) — Android has no coach to sell. A one-time-
purchase Review paywall (mirroring iOS's Review plan, no Pro/subscription
equivalent) is planned but **not yet implemented** — see the Status section.

## Status: builds and tests green, real Stockfish binary bundled

A later session had a real Android SDK (build-tools/platforms up to API 37.1),
NDK 28.2.13676358, and reachable `dl.google.com`/JitPack/GitHub, and used them to
actually verify this module end to end:

- **`core/` builds and its full test suite passes** (chess rules, perft, UCI
  engine client, data parsing — 22 tests, 0 failures). See
  [Verifying `core/`](#verifying-core).
- **`app/` builds clean** (`gradle :app:assembleDebug` — `BUILD SUCCESSFUL`) on
  current stable tooling: AGP 9.3.1, Kotlin 2.4.10, Compose BOM 2026.08.00,
  `compileSdk`/`targetSdk` 37 (the Compose BOM's transitive deps require at
  least 37; 36 fails `checkDebugAarMetadata`). AGP 9 folds Kotlin support into
  the Android Gradle Plugin itself, so there's no separate
  `org.jetbrains.kotlin.android` plugin anymore — see the `plugins {}` blocks in
  `build.gradle.kts`/`app/build.gradle.kts` for the current shape.
- **A real Stockfish binary is bundled** at
  `app/src/main/jniLibs/arm64-v8a/libstockfish.so`, cross-compiled from a fresh
  `official-stockfish/Stockfish` clone with the NDK (`ARCH=armv8 COMP=ndk`),
  stripped. `EngineProvider.isEngineAvailable` is now true on an arm64-v8a
  device out of the box. Only arm64-v8a is built (per the original plan below —
  it covers the overwhelming majority of real devices); add
  armeabi-v7a/x86_64 the same way for older-device/emulator coverage.
- **Adaptive launcher icon added** (`res/mipmap-anydpi-v26/ic_launcher.xml` +
  `drawable-v26/ic_launcher_foreground.png`/`ic_launcher_monochrome.png` +
  `@color/ic_launcher_background`), extracted from the iOS
  `AppIcon.appiconset` icon via a high-pass filter (the icon's background is a
  soft gradient, not flat, so a single global color threshold pulled in a false
  "halo" — subtracting a heavily-blurred copy of the same image isolates just
  the crown+glow). Checked against the 66dp/108dp adaptive-icon safe zone
  (fits with margin, no clipping under a circular mask).
- **Smoke-tested on a real arm64-v8a emulator (API 34)**: installed, launched,
  no crash. Home screen and navigation work; Puzzles catalog loads from the
  bundled JSON assets. Play mode's full loop was exercised end to end -- moved
  e4, the bundled Stockfish binary actually ran as a subprocess and replied
  with c5, and the move was graded ("Excellent") -- confirming the
  binary/UCI/grading pipeline genuinely works on-device, not just in theory.
- **Not yet done**: Play Store listing, release signing, and the Review
  paywall itself (RevenueCat has no Android app registered for this project
  yet -- only "ChessCoach iOS" and a Test Store app exist under project
  `proj036b7966`; the `review_lifetime` entitlement is there and shareable,
  but the Android app entry, its Play Billing product, and the paywall UI/
  gating code all still need to be built).

### A real correction this session's build caught: no more "Big"/"Small" nets

The original plan (written from training-data knowledge of an older Stockfish)
assumed today's Stockfish still ships two NNUE networks (`EvalFile`+
`EvalFileSmall`) the way it did for a while. **That's no longer true.** A fresh
clone's `evaluate.h` defines exactly one `EvalFileDefaultName`, and `engine.cpp`
registers exactly one `EvalFile` UCI option — the small-net asset
(`nn-37f18f62d772.nnue`) and `EnginePool`'s `nnueSmallPath`/`nnueBigPath`
plumbing this build originally shipped were dead code for the version actually
being bundled, so both were removed. Current Stockfish `incbin`s its one
default network straight into the binary at compile time (that's the bulk of
`libstockfish.so`'s ~95MB — the net alone is ~98.5MB uncompiled, the binary
strips to ~95MB), so `EngineProvider` no longer copies or wires up any net
asset at all: it just leaves `EvalFile` at its built-in default. This is also
strictly safer against a version mismatch — a net file bundled separately has
to match the exact NNUE format version of whatever binary loads it, and the
embedded net is guaranteed to match itself.

## Getting it running

1. Open `android/` as a project in Android Studio (Meerkat/2026.x or newer —
   needs AGP 9.3+, Kotlin 2.4+). `local.properties`/`sdk.dir` is gitignored
   and machine-specific — Android Studio regenerates it itself on sync. See
   the toolchain note below if Gradle can't auto-detect a JDK 17.
2. The arm64-v8a Stockfish binary is already bundled — real devices (which are
   overwhelmingly arm64) work out of the box. Add other ABIs (below) only for
   older-device/emulator coverage.
3. Run on a device or emulator (`minSdk 26`).

### JDK toolchain note

`core/build.gradle.kts` declares `kotlin { jvmToolchain(17) }`, which needs
Gradle to actually find a JDK 17 — plain auto-detection can fail with
"Toolchain download repositories have not been configured" even when one is
installed, if it isn't registered wherever Gradle's toolchain service looks
(e.g. a Homebrew-installed JDK isn't picked up by `/usr/libexec/java_home`).
If you hit that, pin it in your **global**, untracked `~/.gradle/gradle.properties`
(never the repo's own tracked `android/gradle.properties` — that file is
shared, and a hardcoded path only exists on one machine):
`org.gradle.java.home=/path/to/a/jdk-17`. Find candidates with
`/usr/libexec/java_home -V` or `brew --prefix openjdk@17`.

## The Stockfish binary

Every screen that needs the engine (Play mode's opponent + grading, Review
mode's eval) checks `EngineProvider.isEngineAvailable` and degrades to a clear
in-UI message rather than crashing when it's false. Puzzles, Lessons, and the
Opening Trainer need no engine at all and work regardless.

Android (API 29+) won't execute an arbitrary file from app-writable storage, so
Stockfish is shipped as if it were a native library — `libstockfish.so` per ABI
under `jniLibs/`, which Android *is* willing to execute — and then run as a
child process talking plain UCI over stdin/stdout (`EngineProvider` resolves
`applicationInfo.nativeLibraryDir/libstockfish.so` and hands that path to
`core`'s `EnginePool`, which is otherwise identical to iOS's `EnginePool`:
same caching, same weighted-sampling "human-like" opponent). This is the same
technique real published Android chess engines use, not a hack specific to
this app.

arm64-v8a is already built and bundled. To add another ABI:

```bash
git clone https://github.com/official-stockfish/Stockfish
cd Stockfish/src
# armeabi-v7a example -- adjust ARCH/toolchain triple per ABI:
make -j build ARCH=armv7 COMP=ndk \
    CXX=$ANDROID_NDK/toolchains/llvm/prebuilt/*/bin/armv7a-linux-androideabi26-clang++
$ANDROID_NDK/toolchains/llvm/prebuilt/*/bin/llvm-strip stockfish
cp stockfish $ANDROID_PROJECT/app/src/main/jniLibs/armeabi-v7a/libstockfish.so
```

(Exact `ARCH`/toolchain flags depend on your NDK version and target ABI — see
Stockfish's own `src/Makefile` help, e.g. `ARCH=x86_64`+
`x86_64-linux-android21-clang++` for the emulator. Building a static,
non-PIE-safe binary matters here since it's being loaded from
`nativeLibraryDir`, not `dlopen`'d — the default `make build` already produces
that.)

No NNUE net needs bundling separately — see the correction above.

## What's here vs. what's dropped

Ported (engine-only, matching the iOS feature *behavior*, not code):

- Full legal chess rules (`core/chess/`) — independently written, not
  transliterated, and checked against perft, not just spot-checked.
- `EnginePool` (`core/engine/`) — same UCI caching/sampling contract as iOS,
  driven over a subprocess instead of ChessKitEngine.
- Puzzles, ECO opening lookup/trainer, and the Lessons curriculum
  (`core/data/`) — the puzzle JSON, ECO TSVs, and licenses are copied verbatim
  from `Sources/GemmaChessCore/Resources/`; `LessonCatalog.kt` is a line-by-line
  port of the Swift literal.
- Play (grading via centipawn loss, hints, take-back, opening recognition),
  Review (PGN import + step-through + eval), Puzzles, Lessons, Opening
  Trainer, Settings/licenses — one Compose screen each under `app/.../ui/`.

Deliberately not ported (per this build's review-only scope):

- `ManagedCoach`/`GeminiCoach`, BYOK settings, per-move written coaching,
  free-form Q&A, end-of-game LLM debriefs, Weakness Report, Sync,
  Announcements, ReviewPrompt, onboarding paywall slides. All of that is the
  Pro tier's LLM surface, and Android has no coach at all -- deliberately, not
  just "not yet ported."

## Verifying `core/`

```bash
cd android
gradle :core:test
```

22 tests: perft against the standard start/Kiwipete/promotion reference
positions plus a hand-verified en passant position, FEN/SAN/PGN round-trips,
checkmate/stalemate detection, a scripted-UCI-response test of `EnginePool`
(no real binary needed), and data-loading tests for puzzles/ECO/lessons.

## Verifying `app/`

```bash
cd android
gradle :app:assembleDebug
```
