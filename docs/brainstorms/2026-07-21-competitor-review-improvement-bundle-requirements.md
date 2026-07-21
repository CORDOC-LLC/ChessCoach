---
title: Competitor-Review-Driven Improvement Bundle
date: 2026-07-21
---

# Competitor-Review-Driven Improvement Bundle

## Problem Frame

Research into App Store/review feedback for Dr. Wolf, Noctie, chess.com, and Lichess surfaced five concrete, actionable gaps against ChessCoach's current state — each tied to a specific competitor complaint or praise pattern, not a generic "improve the app" ask. All five are constrained to run entirely on-device or against free, optional third-party public APIs: **zero calls to ChessCoach's own gateway, zero LLM calls, no new heavy dependencies, no app bloat, and every network/parse path must fail soft (never crash the app).** This preserves the free tier's cost profile — none of this work changes what's Pro-gated.

Priorities remain, in order: virality, utility that converts to App Store ratings, monetization. This bundle is squarely aimed at the first two.

## Scope: Five Features

### 1. Human-Like Engine Opponent

**Complaint addressed:** Dr. Wolf's top complaint — "plays the same openings every time," feels robotic. Noctie's top praise — "plays like a human, not an engine."

**Decision:** An explicit **"Human-like" toggle** in Play's game-setup screen, **off by default**. When enabled:
- **Opening variety:** the engine's opening moves are drawn from the bundled ECO book with randomized selection among plausible book lines, for the first several plies.
- **Move sampling:** at lower skill settings only, replies are chosen via weighted random sampling over the engine's top MultiPV candidate lines (already supported by `EnginePool`) rather than always the single best move — so imperfection looks like a plausible near-best human choice, not noise.

**Explicitly NOT in scope:** relying on Stockfish's own "Skill Level" imprecision alone (considered, rejected — doesn't target the "human vs random" complaint directly). High-skill/Expert-level play is unaffected by either effect regardless of the toggle, preserving current difficulty at the top end.

### 2. Import Games by Username

**Complaint addressed:** the Weakness Report (already shipped) only has data from games played inside ChessCoach or manually pasted into Review — most competitive players' real game history lives on chess.com or Lichess.

**Decision:** A new tab inside the existing Import screen ("From a username," alongside the current paste-a-PGN flow). Supports both chess.com and Lichess public game-export APIs (no auth required, free, optional/best-effort). Fetches the **last 10 games** for the given username and presents them as a browsable list — **no automatic analysis**. Opening/reviewing an imported game works exactly like opening any other saved game; that's what actually triggers Stockfish analysis and, in turn, feeds the Weakness Report.

**Failure handling:** a single generic message covers every failure mode (private profile, wrong username, no games played, unreachable API) — no attempt to distinguish network failure from "not found."

**Closing the import→report gap:** because analysis only happens on review, importing 10 games does not automatically give the Weakness Report 10 games of data — only the ones the user actually opens count. After a successful import, show a light nudge pointing the user toward reviewing a few of the freshly-imported games (not automation, not a hard requirement).

### 3. Free Local "Why" Hint Explanations

**Complaint addressed:** Dr. Wolf's hints "don't explain why" a move is recommended.

**Decision:** Template-based, one-line rationales built entirely from facts Stockfish already computes for the existing free hint (e.g., a hanging piece, a mate threat, a material gain, a newly-defended square) — no LLM, no network. Shown alongside the existing hint UI. Visually **labeled as free/engine-tier** (a small tag or similar), distinguishing it from wherever the Pro coach's richer explanations are marked elsewhere in the app — the exact visual treatment is left to implementation, but the intent is a clear, low-key "this is the free version" signal, not a value judgment on it.

### 4. Shareable Result Cards

**Opportunity:** competitor research didn't surface a direct complaint here — this is the one deliberate virality play in the bundle, since a single-player app has few natural sharing loops.

**Decision:** v1 covers two trigger points only: **game-over** (a finished Play game) and **puzzle-streak milestones**. Each renders a shareable image card into the iOS share sheet. Puzzle-session-complete (non-streak) and Weakness Report cards are explicitly deferred (see below).

### 5. Free-Tier Messaging

**Opportunity:** chess.com's one-star reviews consistently cite paywalled puzzles/lessons and daily caps — ChessCoach's free tier already has none of that, but never says so.

**Decision:** one new onboarding slide stating what's free (no ads, no daily puzzle cap, no cheaters) added to the existing onboarding flow. App Store description copy is a separate, non-code deliverable (a text file), not an in-app UI element.

---

## Key Decisions & Rationale

| Decision | Rationale |
|---|---|
| Human-like toggle is opt-in, off by default | User's explicit choice, overriding the default-on recommendation — preserves current behavior as the baseline; human-like play is something a player chooses, not an invisible change to how the app already played. |
| Both effects (opening variety + move sampling) gate on lower skill only | Keeps Expert-level difficulty exactly as it is today; the "feels robotic" complaint is most relevant at the skill levels beginners/intermediate players actually use. |
| Import is browse-and-pick, not auto-analyze | Auto-analyzing ~10-20 games on-device costs real CPU/battery with no existing progress UI to show for it; browse-and-pick reuses the existing Review/analysis flow exactly, at zero added on-device cost until the user chooses to spend it. |
| Both chess.com and Lichess supported in v1 | The point of this feature is capturing players who play *elsewhere* — supporting only one of the two dominant platforms would leave out a large share of the target audience. |
| Weighted MultiPV sampling over relying on Skill Level noise alone | `EnginePool` already supports MultiPV; sampling among top candidate lines produces errors that look like plausible near-best human choices, directly addressing "plays randomly" rather than "plays imperfectly." |
| Post-import nudge (not automation) to close the import→report gap | Keeps the on-device cost model unchanged (analysis stays user-triggered) while still surfacing the connection to the Weakness Report so the import feature's stated purpose isn't silently unmet. |

## Scope Boundaries

### Deferred for later
- Puzzle-session-complete (non-streak) share cards
- Weakness Report share cards (exposes semi-personal weakness data to a share sheet — needs its own consideration)
- Distinguishing network-failure vs. not-found error states for username import
- A user-adjustable fetch count for username import (fixed at 10 for v1)
- Surfacing free-tier messaging in Settings in addition to onboarding

### Outside this bundle's scope entirely
- Any change to Pro-gated coach behavior, prompts, or the gateway
- Any new backend endpoint or LLM call
- Deeper engine-analysis features or coach personality customization (separate, previously-discussed paid-surface ideas — not touched here)

## Outstanding Questions

None blocking — every fork surfaced during dialogue was resolved during this brainstorm. Implementation-time specifics (exact API response parsing, exact template wording for hint rationales, exact card visual design) are left to planning/execution.

## Success Criteria

- Human-like toggle exists in Play setup, defaults off, and measurably varies openings/move choices only when on and only at lower skill.
- A user can import the last 10 games for a chess.com or Lichess username from the Import screen and browse them like any saved game, with a working nudge toward reviewing some after import.
- The free hint shows a one-line "why" explanation with no network call, visually marked as free-tier.
- Game-over and puzzle-streak-milestone screens each offer a working share-sheet card.
- Onboarding includes a free-tier messaging slide; App Store copy exists as a deliverable text file.
- None of the above ever crashes the app on failure (bad network, bad API response, missing engine line, etc.) — all fail soft to a safe default.

## Sources & Research

Grounded in this session's earlier competitor review research (Dr. Wolf, Noctie, chess.com, Lichess App Store/review findings) and this repo's existing architecture: `EnginePool`/`GCConfig` (MultiPV support), `Openings.lines` (bundled ECO book, lazily parsed), `GameImportView` + `ReviewViewModel` + `HistoryStore.recordGame` (existing import/analysis pipeline), `PuzzleStreakStore`/`PlayStatsStore`, `PlayViewModel.requestHint`/`HintInfo` (existing free hint), `OnboardingView` (existing onboarding flow).
