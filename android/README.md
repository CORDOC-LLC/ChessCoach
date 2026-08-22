# ChessCoach for Android

A Kotlin/Jetpack Compose port of ChessCoach, living entirely under `android/` so it
doesn't touch the existing Swift app (`Sources/`, `Apps/`). Same contract as iOS:
**Stockfish computes, nothing else does.** This build ships the **review tier
only** — engine play, grading, hints, puzzles, lessons, and the opening trainer,
all on-device. There is no coach (no LLM prose, no BYOK/managed-coach settings),
no account, and no network calls anywhere in the app.

## Status: source-complete, build-unverified

Everything below was written in a sandboxed session with **no Android SDK, no
NDK, and no reachable `dl.google.com`/JitPack** (only Maven Central was
reachable). That means:

- **`core/` is real and verified.** It's a pure-Kotlin/JVM module with zero
  Android dependency, and its full test suite (chess rules, perft, UCI engine
  client, data parsing — 22 tests) actually ran and passed in this sandbox. See
  [Verifying `core/`](#verifying-core) to reproduce that.
- **`app/` (the Compose UI) is written but never compiled.** The Android Gradle
  Plugin couldn't even be resolved here (`dl.google.com` is blocked), so nothing
  in `app/` has been built, run, or seen a device/emulator. Treat it as a
  careful first draft: open it in Android Studio, let Gradle sync pull the
  missing pieces, and expect to fix the usual first-build snags.
- **No compiled Stockfish binary is bundled.** See
  [The Stockfish binary](#the-stockfish-binary) — this is the one piece that
  needs a real Android NDK toolchain to produce, which this sandbox doesn't
  have either.

## Getting it running

1. Open `android/` as a project in Android Studio (Ladybug/2024.2+ recommended
   — needs AGP 8.7, Kotlin 2.0). Let it sync; this generates the Gradle wrapper
   and pulls the Android SDK/AGP from `google()`, none of which this sandbox
   could reach.
2. Build the Stockfish binary (below) and drop it into `jniLibs/`.
3. Run on a device or emulator (`minSdk 26`).

## The Stockfish binary

Every screen that needs the engine (Play mode's opponent + grading, Review
mode's eval) checks `EngineProvider.isEngineAvailable` and degrades to a clear
in-UI message rather than crashing when it's false — that's the state the app
ships in until you add the binary. Puzzles, Lessons, and the Opening Trainer
need no engine at all and work immediately.

Android (API 29+) won't execute an arbitrary file from app-writable storage, so
Stockfish is shipped as if it were a native library — `libstockfish.so` per ABI
under `jniLibs/`, which Android *is* willing to execute — and then run as a
child process talking plain UCI over stdin/stdout (`EngineProvider` resolves
`applicationInfo.nativeLibraryDir/libstockfish.so` and hands that path to
`core`'s `EnginePool`, which is otherwise identical to iOS's `EnginePool`:
same caching, same weighted-sampling "human-like" opponent). This is the same
technique real published Android chess engines use, not a hack specific to
this app.

To produce it:

```bash
git clone https://github.com/official-stockfish/Stockfish
cd Stockfish/src
# Repeat per ABI you want to ship (arm64-v8a covers the overwhelming majority
# of real devices; add armeabi-v7a/x86_64 for older/emulator coverage).
make -j build ARCH=armv8 COMP=ndk \
    CXX=$ANDROID_NDK/toolchains/llvm/prebuilt/*/bin/aarch64-linux-android29-clang++
cp stockfish $ANDROID_PROJECT/app/src/main/jniLibs/arm64-v8a/libstockfish.so
```

(Exact `ARCH`/toolchain flags depend on your NDK version — see Stockfish's own
`src/Makefile` help. Building a static, non-PIE-safe binary matters here since
it's being loaded from `nativeLibraryDir`, not `dlopen`'d.)

The NNUE net actually bundled (`app/src/main/assets/nnue/nn-37f18f62d772.nnue`,
~3.5MB) is Stockfish's smaller network — deliberately not the ~75MB primary net
iOS ships, to keep this new module's footprint reasonable. `EngineProvider`
wires it up as `EvalFileSmall` only, so play strength is somewhat below the iOS
app's. Drop the bigger net in and wire up `EvalFile` too in
`EngineProvider.createEnginePool()` if you want full strength.

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

- `ManagedCoach`/`GeminiCoach`, BYOK settings, RevenueCat/paywall, per-move
  written coaching, free-form Q&A, end-of-game LLM debriefs, Weakness Report,
  Sync, Announcements, ReviewPrompt, onboarding paywall slides. All of that is
  the Pro tier's LLM surface; this build is review-only and offline-only.

## Verifying `core/`

`core/` has no Android dependency, so it's the one part of this module a
sandbox without an Android SDK can actually build and test:

```bash
cd android/core
# core/build.gradle.kts uses the version-less `kotlin("jvm")` plugin form,
# which relies on the root project's plugin management to supply a version --
# standalone, add one directly (or just open the whole android/ project in
# Android Studio, where the root project supplies it automatically):
#   sed -i 's/kotlin("jvm")$/kotlin("jvm") version "2.0.21"/' build.gradle.kts
# and give it its own tiny settings.gradle.kts pointing at mavenCentral().
gradle test
```

22 tests: perft against the standard start/Kiwipete/promotion reference
positions plus a hand-verified en passant position, FEN/SAN/PGN round-trips,
checkmate/stalemate detection, a scripted-UCI-response test of `EnginePool`
(no real binary needed), and data-loading tests for puzzles/ECO/lessons.
