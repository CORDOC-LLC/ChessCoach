# ChessCoach

A native **iOS + macOS** chess app where Stockfish plays and grades, and an
LLM explains — in plain English, move by move — why. Not a chess engine
wearing a chat window: the engine decides everything (best move, evaluation,
grade); the model only puts that verdict into words.

Play a full game against Stockfish (adjustable strength) with live coaching
after every move, or paste/import a finished game for a full post-game
review.

**The engine always runs fully on-device** — Stockfish is compiled directly
into the app (via
[chesskit-engine](https://github.com/chesskit-app/chesskit-engine)), so every
move evaluation, grade, best-move calculation, and opening lookup happens
locally with no network involved, full stop. The coach's *written
explanation* is the one piece that requires a network call — there is no
on-device coach model (Apple Foundation Models and Gemma 3n via MLX were both
tried and dropped; quality wasn't good enough to ship). You opt into one of:

1. **ChessCoach Pro** (developer-hosted, metered) — if configured
2. **Your own Gemini API key** (BYOK) — if you've added one in Coach Settings

If neither is configured, the app still gives full engine review — grades,
best moves, evaluations — just without written coaching.

If a configured backend fails, **the app shows the error — it does not
silently fall back to a different backend.** That's deliberate: a silent
fallback would hide a real problem (a bad deploy, an expired key, a network
outage) behind output that looks fine but quietly downgraded. The engine-only
review always still works regardless; only the coach's prose is affected.

A native Swift reimplementation of
[tintins-chess-analysis](https://github.com/Chess-analysis-mcp/tintins-chess-analysis).
The defining contract, inherited from that project: **Stockfish computes; the
model only explains.** The LLM never reasons about chess — it turns
pre-computed engine facts into plain-English coaching.

## What it does

- **Play mode** — pick a side, play against Stockfish at a chosen skill
  level, get a short coach note after every move (grounded in the exact
  engine grade — the model never overrides it), and ask the coach free-form
  questions about the position.
- **Live opening recognition** — the game is matched against the Lichess
  `chess-openings` database as you play, so the app names your line ("London
  System") as it's reached, not just after the fact.
- **Opponent-intent coaching** — the per-move note also covers what the
  engine's reply is trying to do, so you're not just told your move was fine,
  you're told what to watch for next.
- **On-demand hints** — best move + a good alternative, with a short
  engine-grounded reason for each, streamed in.
- **Take back and retry** — after a move grades as an inaccuracy or worse,
  rewind it and find the better move yourself.
- **End-of-game debrief** — a short written summary of the game's turning
  points and one thing to work on, built from the moves already graded live.
- **Review mode** — import a PGN (or a Lichess game URL) and step through a
  full engine-graded review with an AI game summary.
- **Usage & cost tracking** — for the optional managed coach tier, see
  exactly how many tokens each coaching call used and what it's estimated to
  cost, over any date range.

## Architecture

- `Sources/GemmaChessCore/` — the cross-platform core (SwiftPM package):
  chess rules, the Stockfish engine wrapper, evaluation math, the coach
  prompt builder, both `CoachLLM` backends (`ManagedCoach`, `GeminiCoach`),
  and all SwiftUI views/view models. Both app targets are thin shells over
  this package.
- `Apps/GemmaChessiOS/`, `Apps/GemmaChessMac/` — the iOS and macOS app
  targets (UI wiring only — no logic lives here).
- `Tests/GemmaChessCoreTests/` — Swift Testing suite (163 tests).
- `docs/plans/` — implementation plans, kept as historical design records.

The managed coach's backend (`chesscoach-gateway`) is a separate, private
repository — a server that never ships to a device carries no GPL
disclosure obligation, and it keeps a Node/TypeScript project out of this
Swift package. See `docs/plans/2026-07-08-001-feat-paid-tier-metering-backend-plan.md`
for the full design (RevenueCat entitlement checks, per-user token metering,
App Attest).

## Build & run

Requires Xcode 26+, iOS 18+ / macOS 15+ deployment targets, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
# Run the cross-platform test suite (no Xcode project needed):
swift test

# Generate the Xcode project (first time: copy local.env.example -> local.env
# and set your own Apple Developer Team ID for code signing):
cp local.env.example local.env
./scripts/gen-project.sh
open GemmaChess.xcodeproj
```

`scripts/install-device.sh` builds and installs onto a connected iPhone/iPad
via `xcrun devicectl`.

## Status

Actively developed. Play mode, Review mode, live opening recognition, hints,
retry, end-of-game debriefs, and BYOK Gemini coaching are all implemented and
tested (163 tests, all passing). The managed coach tier (`ManagedCoach`) is
built and working end-to-end against a real deployment, but currently
gated behind a local debug-testing token — the real App Store subscription
flow (RevenueCat) isn't wired up client-side yet. See `docs/plans/` for the
design history.

## License

**GPLv3.** ChessCoach compiles [Stockfish](https://stockfishchess.org) directly
into the app binary (via
[chesskit-engine](https://github.com/chesskit-app/chesskit-engine)), which
makes the whole combined binary a single GPLv3 work — so the full app source,
this repository, is released under GPLv3 too. See `LICENSE` for the full text
and `NOTICE.md` for every third-party component and its license (Stockfish,
chesskit-swift/engine, the Lichess `chess-openings` dataset). The same
information is available in-app under **Open Source Licenses** on the home
screen.
